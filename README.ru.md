![Kinetrell Duo by Shalfey Predskazatel](assets/kinetrell-duo-cover.png)

# Kinetrell

[English](README.md) · [Скачать последнюю версию](https://github.com/Yamidashka/rtx-video-player/releases/latest) · [Изменения](RELEASE-NOTES.md)

Kinetrell (ранее RTX Video Player) — портативный проигрыватель на базе mpv для Windows 10 и 11 x64. Поддерживает генерацию кадров, NVIDIA RTX Video Super Resolution, RTX Video HDR и интерфейс на русском и английском.

| Редакция | Что внутри | ZIP для Windows x64 |
| --- | --- | --- |
| **VFG** | NVIDIA VFG и Maxine VFX 1.3.0 | [Скачать](https://github.com/Yamidashka/rtx-video-player/releases/download/v1.3.0/Kinetrell-VFG-v1.3.0-Windows-x64.zip) |
| **RIFE** | DirectML и модели 4.4, 4.6 и 4.17 Lite | [Скачать](https://github.com/Yamidashka/rtx-video-player/releases/download/v1.3.0/Kinetrell-RIFE-v1.3.0-Windows-x64.zip) |
| **Duo** | VFG и RIFE в одном плеере, Maxine и DirectML внутри | [Скачать](https://github.com/Yamidashka/rtx-video-player/releases/download/v1.3.0/Kinetrell-Duo-v1.3.0-Windows-x64.zip) |

Распакуйте архив целиком. Запустите `RTX Video Player.exe` для VFG, `RTX Video Player RIFE.exe` для RIFE или `RTX Video Player Combined.exe` для Duo. Чтобы открыть видео, перетащите его на EXE или выберите плеер через «Открыть с помощью».

В Duo генератор выбирается первой кнопкой на панели. Режим «Авто» подбирает целый множитель под частоту кадров видео и монитора. Для ручного режима доступны 2×–6×. Меню качества, модели и разрешения открываются рядом с соответствующими кнопками.

Для VFG нужны совместимая видеокарта NVIDIA RTX и драйвер. Для RTX Video HDR включите HDR в Windows. Если Windows сообщает об отсутствии `MSVCP140.dll` или `VCRUNTIME140.dll`, установите [Microsoft Visual C++ Redistributable x64](https://aka.ms/vc14/vc_redist.x64.exe).

[Контрольные суммы](SHA256SUMS.txt) · [Сборка исходников](BUILD.md) · [Опциональный TensorRT](TENSORRT.md) · [Сторонние компоненты](THIRD-PARTY.md)
