import os
from fractions import Fraction
from pathlib import Path

import vapoursynth as vs

core = vs.core
plugins = Path(os.environ["VAPOURSYNTH_PLUGIN_PATH"])
multiplier, model = (int(value) for value in user_data.split("-"))
if not 2 <= multiplier <= 6 or model not in (4171, 44, 46):
    raise ValueError("Unsupported RIFE multiplier or model")

tensorrt = model == 4171 and (plugins / "vstrt.dll").is_file() and (
    plugins / "vsmlrt-cuda" / "nvinfer_10.dll"
).is_file()
namespace, plugin = ("trt", "vstrt.dll") if tensorrt else ("ort", "vsort.dll")
if not hasattr(core, namespace):
    core.std.LoadPlugin(str(plugins / plugin))
if not hasattr(core, "misc"):
    core.std.LoadPlugin(str(plugins / "MiscFilters.dll"))

from vsmlrt import Backend, RIFE

if tensorrt:
    backend = Backend.TRT(fp16=True, num_streams=2, output_format=1, use_cuda_graph=True)
else:
    backend = Backend.ORT_DML(fp16=True, num_streams=1, output_format=1)

core.num_threads = min(os.cpu_count() or 1, 12)
core.max_cache_size = 2048
clip = video_in
matrix = 1 if clip.width > 1024 or clip.height >= 600 else 5
if clip.format.color_family == vs.YUV:
    luma = core.std.ShufflePlanes(clip, 0, vs.GRAY)
    clip = core.resize.Bicubic(clip, format=vs.RGBH, matrix_in=matrix, prefer_props=True)
else:
    luma = core.resize.Bilinear(clip, format=vs.GRAY8, matrix=matrix)
    clip = core.resize.Bicubic(clip, format=vs.RGBH)
luma = core.misc.SCDetect(luma, threshold=0.10)

pad_w = (-clip.width) % 32
pad_h = (-clip.height) % 32
if pad_w or pad_h:
    clip = core.std.AddBorders(clip, right=pad_w, bottom=pad_h)
clip = core.std.CopyFrameProps(clip, luma, props=["_SceneChangePrev", "_SceneChangeNext"])
clip = RIFE(clip, multi=multiplier, model=model, _implementation=2, backend=backend)
if pad_w or pad_h:
    clip = core.std.Crop(clip, right=pad_w, bottom=pad_h)
clip = core.resize.Bicubic(clip, format=vs.YUV420P10, matrix=matrix)
fps = Fraction(container_fps).limit_denominator(1001) * multiplier
core.std.AssumeFPS(clip, fpsnum=fps.numerator, fpsden=fps.denominator).set_output()
