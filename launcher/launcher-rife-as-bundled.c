#define _WIN32_WINNT 0x0A00
#include <windows.h>
#include <shellapi.h>

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

enum { PATH_CAP = 32768, COMMAND_CAP = 32767 };
static const wchar_t title[] = L"Проигрыватель RTX Video";

struct player_identity {
    DWORD pid;
    FILETIME created;
};

struct location {
    wchar_t root[PATH_CAP];
    wchar_t engine[PATH_CAP];
    wchar_t config[PATH_CAP];
    wchar_t record[PATH_CAP];
    wchar_t request[PATH_CAP];
    wchar_t staged[PATH_CAP];
    wchar_t processing[PATH_CAP];
};

static int report_error(const wchar_t *message)
{
    MessageBoxW(NULL, message, title, MB_OK | MB_ICONERROR | MB_SETFOREGROUND);
    return 1;
}

static wchar_t *absolute_filename(const wchar_t *name)
{
    DWORD size = GetFullPathNameW(name, 0, NULL, NULL);
    wchar_t *result = size ? malloc(size * sizeof(*result)) : NULL;
    if (result) {
        DWORD used = GetFullPathNameW(name, size, result, NULL);
        if (used && used < size)
            return result;
    }
    free(result);
    return NULL;
}

static bool find_location(struct location *place)
{
    DWORD length = GetModuleFileNameW(NULL, place->root, PATH_CAP);
    if (!length || length >= PATH_CAP)
        return false;
    wchar_t *separator = wcsrchr(place->root, L'\\');
    if (!separator)
        return false;
    // Preserve the backslash in a volume root such as C:\.
    separator[separator == place->root + 2] = L'\0';
    const wchar_t *join = separator == place->root + 2 ? L"" : L"\\";
    return swprintf(place->engine, PATH_CAP, L"%ls%lsbin\\mpv.exe", place->root, join) >= 0 &&
        swprintf(place->config, PATH_CAP, L"%ls%lsportable_config", place->root, join) >= 0 &&
        swprintf(place->record, PATH_CAP, L"%ls\\.launcher-player", place->config) >= 0 &&
        swprintf(place->request, PATH_CAP, L"%ls\\.launcher-open.json", place->config) >= 0 &&
        swprintf(place->staged, PATH_CAP, L"%ls\\.launcher-open.tmp", place->config) >= 0 &&
        swprintf(place->processing, PATH_CAP, L"%ls\\.launcher-processing.json", place->config) >= 0;
}

static uint64_t package_id(const wchar_t *directory)
{
    wchar_t path[PATH_CAP];
    wcscpy(path, directory);
    CharLowerBuffW(path, (DWORD)wcslen(path));
    uint64_t hash = UINT64_C(14695981039346656037);
    for (const wchar_t *p = path; *p; p++) {
        hash ^= *p;
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}

// Quote an argument for Windows CRT parsing, including trailing backslashes.
static bool append_argument(wchar_t *command, size_t *length, const wchar_t *arg)
{
    size_t needed = 2 * wcslen(arg) + 4;
    if (*length + needed > COMMAND_CAP)
        return false;
    wchar_t *out = command + *length;
    if (*length)
        *out++ = L' ';
    *out++ = L'"';
    const wchar_t *p = arg;
    for (;;) {
        size_t slashes = 0;
        while (*p == L'\\') {
            slashes++;
            p++;
        }
        if (!*p || *p == L'"')
            slashes *= 2;
        while (slashes--)
            *out++ = L'\\';
        if (!*p)
            break;
        if (*p == L'"')
            *out++ = L'\\';
        *out++ = *p++;
    }
    *out++ = L'"';
    *out = L'\0';
    *length = out - command;
    return true;
}

static bool publish(const struct location *place, const wchar_t *target,
                    const void *data, DWORD size)
{
    HANDLE stream = CreateFileW(place->staged, GENERIC_WRITE, 0, NULL,
                                CREATE_ALWAYS, FILE_ATTRIBUTE_HIDDEN, NULL);
    if (stream == INVALID_HANDLE_VALUE)
        return false;
    DWORD written = 0;
    bool saved = WriteFile(stream, data, size, &written, NULL) && written == size;
    CloseHandle(stream);
    if (saved && MoveFileExW(place->staged, target, MOVEFILE_REPLACE_EXISTING))
        return true;
    DeleteFileW(place->staged);
    return false;
}

static bool player_creation(HANDLE process, FILETIME *created)
{
    FILETIME exit, kernel, user;
    return GetProcessTimes(process, created, &exit, &kernel, &user);
}

static HANDLE find_player(const struct location *place, DWORD *pid)
{
    HANDLE stream = CreateFileW(place->record, GENERIC_READ, FILE_SHARE_READ,
                                NULL, OPEN_EXISTING, 0, NULL);
    if (stream == INVALID_HANDLE_VALUE)
        return GetLastError() == ERROR_FILE_NOT_FOUND ? NULL : INVALID_HANDLE_VALUE;
    struct player_identity identity;
    DWORD read;
    bool valid = ReadFile(stream, &identity, sizeof(identity), &read, NULL) &&
        read == sizeof(identity) && identity.pid;
    CloseHandle(stream);
    if (!valid)
        return NULL;
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE,
                                 FALSE, identity.pid);
    if (!process)
        return GetLastError() == ERROR_INVALID_PARAMETER ? NULL : INVALID_HANDLE_VALUE;
    wchar_t image[PATH_CAP];
    DWORD size = PATH_CAP;
    FILETIME created;
    if (WaitForSingleObject(process, 0) != WAIT_TIMEOUT ||
        !player_creation(process, &created) || CompareFileTime(&created, &identity.created) ||
        !QueryFullProcessImageNameW(process, 0, image, &size) ||
        CompareStringOrdinal(image, -1, place->engine, -1, TRUE) != CSTR_EQUAL) {
        CloseHandle(process);
        return NULL;
    }
    *pid = identity.pid;
    return process;
}

static BOOL CALLBACK show_player_window(HWND window, LPARAM process_id)
{
    DWORD owner = 0;
    GetWindowThreadProcessId(window, &owner);
    if (owner != (DWORD)process_id || !IsWindowVisible(window) ||
        GetWindow(window, GW_OWNER))
        return TRUE;
    if (IsIconic(window))
        ShowWindowAsync(window, SW_RESTORE);
    SetForegroundWindow(window);
    return FALSE;
}

static char *create_request(wchar_t **files, int count)
{
    size_t size = 3;
    for (int i = 0; i < count; i++)
        size += 6 * wcslen(files[i]) + 4;
    char *request = malloc(size), *utf8 = malloc(3 * PATH_CAP);
    if (!request || !utf8) {
        free(request);
        free(utf8);
        return NULL;
    }
    char *out = request;
    *out++ = '[';
    const char digits[] = "0123456789abcdef";
    for (int i = 0; i < count; i++) {
        if (!WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, files[i], -1, utf8,
                                 3 * PATH_CAP, NULL, NULL)) {
            free(request);
            free(utf8);
            return NULL;
        }
        if (i)
            *out++ = ',';
        *out++ = '"';
        for (const unsigned char *p = (unsigned char *)utf8; *p; p++) {
            if (*p < 0x20) {
                memcpy(out, "\\u00", 4);
                out += 4;
                *out++ = digits[*p >> 4];
                *out++ = digits[*p & 15];
                continue;
            }
            if (*p == '\\' || *p == '"')
                *out++ = '\\';
            *out++ = (char)*p;
        }
        *out++ = '"';
    }
    *out++ = ']';
    *out = '\0';
    free(utf8);
    return request;
}

static bool no_file(const wchar_t *path)
{
    return GetFileAttributesW(path) == INVALID_FILE_ATTRIBUTES &&
        GetLastError() == ERROR_FILE_NOT_FOUND;
}

static int forward_files(const struct location *place, HANDLE process,
                         wchar_t **files, int count)
{
    char *request = create_request(files, count);
    if (!request)
        return 1;
    bool saved = publish(place, place->request, request, (DWORD)strlen(request));
    free(request);
    if (!saved)
        return 1;
    for (unsigned attempt = 0; attempt < 100; attempt++) {
        // The receiver claims the request by renaming it, then deletes it
        // after mpv has accepted the loadfile commands.
        if (no_file(place->request) && no_file(place->processing))
            return 0;
        if (WaitForSingleObject(process, 60) == WAIT_OBJECT_0)
            return -1;
    }
    return 1;
}

static bool configure_rife_runtime(const wchar_t *root)
{
    wchar_t plugins[PATH_CAP], vsscript[PATH_CAP];
    if (swprintf(plugins, PATH_CAP, L"%ls\\VS\\vs-plugins", root) < 0 ||
        swprintf(vsscript, PATH_CAP, L"%ls\\VS\\Lib\\site-packages\\vapoursynth\\vsscript.dll", root) < 0 ||
        GetFileAttributesW(vsscript) == INVALID_FILE_ATTRIBUTES)
        return false;

    wchar_t *old_path = calloc(COMMAND_CAP, sizeof(*old_path));
    wchar_t *path = calloc(COMMAND_CAP, sizeof(*path));
    bool ok = false;
    if (old_path && path && GetEnvironmentVariableW(L"PATH", old_path, COMMAND_CAP) < COMMAND_CAP &&
        swprintf(path, COMMAND_CAP, L"%ls\\vsort;%ls\\vsmlrt-cuda;%ls;%ls\\VS\\Lib\\site-packages\\vapoursynth;%ls\\VS;%ls",
                 plugins, plugins, plugins, root, root, old_path) >= 0) {
        ok = SetEnvironmentVariableW(L"PATH", path) &&
             SetEnvironmentVariableW(L"VAPOURSYNTH_PLUGIN_PATH", plugins) &&
             SetEnvironmentVariableW(L"VSSCRIPT_PATH", vsscript);
    }
    free(old_path);
    free(path);
    return ok;
}
static int start_player(const struct location *place, wchar_t **files, int count)
{
    if (!configure_rife_runtime(place->root))
        return report_error(L"Не удалось загрузить среду RIFE. Распакуйте архив целиком.");
    wchar_t command[COMMAND_CAP], config[PATH_CAP];
    if (swprintf(config, PATH_CAP, L"--config-dir=%ls", place->config) < 0)
        return report_error(L"Слишком длинный путь к папке плеера.");
    const wchar_t *options[] = {place->engine, config, L"--no-terminal",
        L"--keep-open=no", count ? L"--idle=no" : L"--idle=once",
        count ? L"--" : L"--force-window=yes"};
    size_t length = 0;
    for (size_t i = 0; i < ARRAYSIZE(options); i++) {
        if (!append_argument(command, &length, options[i]))
            return report_error(L"Слишком длинная команда запуска плеера.");
    }
    for (int i = 0; i < count; i++) {
        if (!append_argument(command, &length, files[i]))
            return report_error(L"Слишком длинный путь к видео.");
    }
    DeleteFileW(place->request);
    DeleteFileW(place->processing);
    STARTUPINFOW startup = {.cb = sizeof(startup)};
    PROCESS_INFORMATION process;
    if (!CreateProcessW(place->engine, command, NULL, NULL, FALSE, CREATE_SUSPENDED,
                        NULL, place->root, &startup, &process))
        return report_error(L"Не удалось запустить bin\\mpv.exe. Распакуйте все файлы из архива.");
    struct player_identity identity = {.pid = process.dwProcessId};
    bool started = player_creation(process.hProcess, &identity.created) &&
        publish(place, place->record, &identity, sizeof(identity)) &&
        ResumeThread(process.hThread) != (DWORD)-1;
    // The launcher owns this process and has not started any playback yet.
    if (!started)
        TerminateProcess(process.hProcess, 1);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    return started ? 0 : report_error(L"Не удалось сохранить состояние запуска. "
                                       L"Распакуйте плеер в доступную для записи папку.");
}

static int dispatch(const struct location *place, wchar_t **files, int count)
{
    DWORD pid;
    HANDLE player = find_player(place, &pid);
    if (player == INVALID_HANDLE_VALUE)
        return report_error(L"Не удалось связаться с запущенным плеером.");
    if (!player)
        return start_player(place, files, count);

    int result = count ? forward_files(place, player, files, count) : 0;
    CloseHandle(player);
    if (!result) {
        EnumWindows(show_player_window, pid);
        return 0;
    }
    if (result < 0)
        return start_player(place, files, count);
    return report_error(L"Плеер не принял команду. Закройте его окно и попробуйте ещё раз.");
}

static int launch(wchar_t **files, int count)
{
    struct location *place = malloc(sizeof(*place));
    if (!place || !find_location(place)) {
        free(place);
        return report_error(L"Не удалось найти папку плеера.");
    }
    // Serialize launches of this portable package within the desktop session.
    wchar_t mutex_name[96];
    swprintf(mutex_name, 96, L"Local\\RtxVideoPlayer.%016llx",
             (unsigned long long)package_id(place->root));
    HANDLE mutex = CreateMutexW(NULL, FALSE, mutex_name);
    int result;
    if (!mutex) {
        result = report_error(L"Не удалось подготовить запуск плеера.");
    } else {
        DWORD lock = WaitForSingleObject(mutex, 15000);
        if (lock == WAIT_OBJECT_0 || lock == WAIT_ABANDONED) {
            result = dispatch(place, files, count);
            ReleaseMutex(mutex);
        } else {
            result = report_error(L"Предыдущее окно плеера ещё запускается.");
        }
        CloseHandle(mutex);
    }
    free(place);
    return result;
}

int WINAPI wWinMain(HINSTANCE app, HINSTANCE previous, PWSTR arguments, int show)
{
    (void)app;
    (void)previous;
    (void)arguments;
    (void)show;
    int argc;
    wchar_t **argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (!argv)
        return report_error(L"Не удалось прочитать путь к видео.");
    wchar_t **files = malloc((size_t)argc * sizeof(*files));
    int result = 1, count = 0;
    if (files) {
        for (int i = 1; i < argc; i++) {
            files[count] = absolute_filename(argv[i]);
            if (!files[count])
                break;
            count++;
        }
        if (count == argc - 1)
            result = launch(files, count);
        else
            report_error(L"Не удалось прочитать путь к видео.");
        for (int i = 0; i < count; i++)
            free(files[i]);
    }
    free(files);
    LocalFree(argv);
    return result;
}


