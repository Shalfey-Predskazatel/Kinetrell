# Third-party components

- **mpv** and the bundled FFmpeg/MSYS2 libraries retain their upstream licenses. The releases include the GPL and LGPL texts, the modified player source and package notices under `licenses`. [mpv source](https://github.com/mpv-player/mpv/tree/1eb941fdb974fe25dc0ac68a33652c145ff41f9d) · [MSYS2 package sources](https://packages.msys2.org/)
- **NVIDIA Maxine Video Effects SDK** supplies VFG on the user's machine. The VFG release uses the separately installed NVIDIA runtime. [SDK installation guide](https://docs.nvidia.com/maxine/vfx/latest/WindowsVFXSDK/InstalltheVFXSDK.html)
- **VapourSynth R79** and **MiscFilters R2** power the RIFE pipeline. The release includes the MiscFilters source and LGPL text. [VapourSynth R79 source](https://github.com/vapoursynth/vapoursynth/tree/R79) · [MiscFilters source](https://github.com/vapoursynth/vs-miscfilters-obsolete)
- **vs-mlrt** supplies `vsort.dll` and the Python wrapper. The RIFE release includes the GPL text and upstream source archives for [the ONNX Runtime plugin v15.13.ort](https://github.com/AmusementClub/vs-mlrt/tree/v15.13.ort) and [the v15.16 wrapper](https://github.com/AmusementClub/vs-mlrt/tree/v15.16).
- **RIFE models** are exported by vs-mlrt and based on [Practical-RIFE](https://github.com/hzwer/Practical-RIFE). [Model downloads](https://github.com/AmusementClub/vs-mlrt/releases/tag/external-models)
- **ONNX Runtime and DirectML** run the model. The included license files and notices are in `VS/licenses`. [ONNX Runtime build source](https://github.com/AmusementClub/onnxruntime/tree/4754a1d64e) · [Microsoft.AI.DirectML 1.15.4](https://www.nuget.org/packages/Microsoft.AI.DirectML/1.15.4)
- **Python** uses the PSF license, included as `VS/LICENSE.txt`. [CPython source](https://github.com/python/cpython)
- **TensorRT** is an optional upstream runtime. [TensorRT license](https://docs.nvidia.com/deeplearning/tensorrt/latest/reference/sla.html)
