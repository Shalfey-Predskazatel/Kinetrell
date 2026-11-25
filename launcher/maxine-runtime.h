/* Configure a private runtime only when the portable package contains it. */
static bool configure_portable_maxine(const wchar_t *root)
{
    wchar_t directory[PATH_CAP];
    wchar_t core[PATH_CAP];
    if (swprintf(directory, PATH_CAP, L"%ls\\Maxine", root) < 0 ||
        swprintf(core, PATH_CAP, L"%ls\\bin\\NVVideoEffects.dll", directory) < 0)
        return false;

    DWORD attributes = GetFileAttributesW(core);
    if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_DIRECTORY))
        return true;

    // The runtime uses narrow Windows paths. Prefer a short path when available.
    wchar_t short_path[MAX_PATH];
    DWORD length = GetShortPathNameW(directory, short_path, ARRAYSIZE(short_path));
    const wchar_t *path = length && length < ARRAYSIZE(short_path) ? short_path : directory;
    return SetEnvironmentVariableW(L"NV_VIDEO_EFFECTS_PATH", path) != 0;
}
