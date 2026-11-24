# Optional TensorRT runtime for RIFE

The release works through DirectML by default and selects RIFE 4.4. TensorRT 10.16 from vs-mlrt v15.16 is an optional runtime for model 4.17 Lite.

1. Close the player. Download `VSTRT-Windows-x64.v15.16.7z` and both parts of `vsmlrt-cuda.v15.16.7z` from the [vs-mlrt v15.16 release](https://github.com/AmusementClub/vs-mlrt/releases/tag/v15.16). Keep the split parts in the same folder.
2. Extract `vstrt.dll` to `VS/vs-plugins/`. Extract the `vsmlrt-cuda` runtime directory from the split archive to `VS/vs-plugins/`, keeping the DLLs and `trtexec.exe` together.
3. Open the player and select **4.17 Lite**. TensorRT builds and caches an engine at the first use of a resolution.

On this machine the existing full RIFE edition already contains the runtime directory and plugin. The offline bundle was tested with the RTX 5060 Laptop GPU.
