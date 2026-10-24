import std/strutils
import softgfx, softgfx/shaders
import ../examples/scene
let mesh = demoMesh()
doAssert mesh.packed.len == 72
doAssert baseline(webgl1).ownerR8 == false
doAssert baseline(gles3).ownerR8
for api in Api:
  doAssert vertexSource(api).contains("aPosition")
  doAssert fragmentSource(api).contains("srgb")
  doAssert fragmentSource(api).startsWith("#version 300 es") == (api in {webgl2, gles3})
var caught = false
try: MeshData().validate()
except ValueError: caught = true
doAssert caught
var r: Renderer
caught = false
try: r.render(100, 100)
except ValueError: caught = true
doAssert caught
r.dispose()
echo "core: OK"

import softgfx/quality
var window: FrameWindow
for i in 1..100: window.add(float32(i))
doAssert window.percentiles == (50'f32, 95'f32)
window.add(NaN.float32)
window.add(Inf.float32)
doAssert window.percentiles.p95 == 95
var scaler = initQuality()
for i in 0..<29: scaler.observe(30)
doAssert scaler.scale == 1
scaler.observe(30)
doAssert abs(scaler.scale - 0.95) < 0.001
for i in 0..<1000: scaler.observe(30)
doAssert scaler.scale == 0.7'f32
for i in 0..<2000: scaler.observe(5)
doAssert scaler.scale == 1
for i in 0..<1000: scaler.observe(1000)
doAssert scaler.scale == 1
echo "quality: OK"
