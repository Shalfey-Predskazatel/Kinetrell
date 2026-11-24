![RTX Video Player — VFG and RIFE](assets/banner.png)

# RTX Video Player

[Русский](README.ru.md) · [Download v1.1.0](https://github.com/Yamidashka/rtx-video-player/releases/tag/v1.1.0)

A portable Windows player based on mpv, with frame generation, NVIDIA RTX Video Super Resolution and RTX Video HDR.

| Edition | Frame generation | Runtime |
| --- | --- | --- |
| VFG | NVIDIA Video Frame Generation | Installed NVIDIA Maxine Video Effects SDK with the VFG feature |
| RIFE | RIFE 4.4, 4.6 or 4.17 Lite | Bundled DirectML, with optional TensorRT for 4.17 Lite |

Download an edition from [**Releases**](https://github.com/Yamidashka/rtx-video-player/releases/latest), extract all files, and launch **RTX Video Player.exe** or **RTX Video Player RIFE.exe**. The VFG or RIFE button opens the generation menu with **Off, 2×, 3×, 4×, 5× and 6×**. Click **RU / EN** to switch the panel and generation menus. Reopen the player to update the **☰** menu.

The player saves settings in its portable configuration folder. Opening another video through the same EXE replaces the current video. For RTX Video HDR, enable HDR in Windows. Playback speed depends on video resolution, model and GPU.

[Инструкция на русском](README.ru.md) · [Build instructions](BUILD.md) · [Optional TensorRT](TENSORRT.md) · [Third-party components](THIRD-PARTY.md)

## Downloads — Windows x64

| Edition | Portable download | Choose this edition when… |
| --- | --- | --- |
| VFG | [Download VFG ZIP](https://github.com/Yamidashka/rtx-video-player/releases/download/v1.1.0/RTX-Video-Player-VFG-v1.1.0.zip) | You have NVIDIA Maxine Video Effects SDK with Video Frame Generation installed. |
| RIFE | [Download RIFE ZIP](https://github.com/Yamidashka/rtx-video-player/releases/download/v1.1.0/RTX-Video-Player-RIFE-v1.1.0.zip) | You want the bundled DirectML frame interpolation runtime. |

Download the portable ZIP, extract it to a writable folder, and run the launcher. The GitHub **Source code** archives contain the project sources, not the ready-to-run player. Keep the full extracted folder together.

The editions share the player and launcher sources in this repository. RIFE uses neural frame interpolation; VFG uses NVIDIA's separately installed runtime. NVIDIA RTX hardware and a compatible driver are required for RTX Video Super Resolution and RTX Video HDR. Available multipliers do not guarantee real-time playback at every resolution.

Verify downloads against [SHA256SUMS.txt](https://github.com/Yamidashka/rtx-video-player/releases/download/v1.1.0/SHA256SUMS.txt). In PowerShell:

```powershell
Get-FileHash .\RTX-Video-Player-RIFE-v1.1.0.zip -Algorithm SHA256
```

## Source and licensing

See [BUILD.md](BUILD.md) for the upstream revision, patch and launcher build steps. Each portable ZIP includes the modified mpv source archive and third-party notices. Project licensing is described in [LICENSE.md](LICENSE.md).

This is a community project based on mpv. It is not an official NVIDIA product.
