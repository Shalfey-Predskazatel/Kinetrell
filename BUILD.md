# Building the Windows player

Both portable releases include the corresponding modified mpv source under `licenses/mpv-rtx-video-source.tar.gz`. The repository also contains a patch for the upstream mpv commit used in the build.

From an MSYS2 CLANG64 environment with mpv build dependencies installed:

```sh
git clone https://github.com/mpv-player/mpv.git
git -C mpv checkout 1eb941fdb974fe25dc0ac68a33652c145ff41f9d
git -C mpv apply ../mpv.patch
meson setup mpv-build mpv --buildtype=release -Dlibmpv=false -Dtests=false \
  -Dmanpage-build=disabled -Dhtml-build=disabled -Dpdf-build=disabled
meson compile -C mpv-build
```

Place the resulting `mpv.exe` and matching shared libraries in `bin`. Use the files under `player/VFG` or `player/RIFE` for the portable configuration. The launcher sources and resources are under `launcher`.

```powershell
pwsh ./Build-Launcher.ps1 -Edition VFG -Destination ./dist/VFG
pwsh ./Build-Launcher.ps1 -Edition RIFE -Destination ./dist/RIFE
```

Reuse the matching runtime tree from the release for testing. The RIFE tree requires VapourSynth R79, embedded CPython 3.15, ONNX Runtime DirectML and the RIFE models listed in [THIRD-PARTY.md](THIRD-PARTY.md).
