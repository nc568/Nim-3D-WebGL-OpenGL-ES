import camera_fixture
import std/jsffi
import softgfx/backends/web
import territory_fixture, instance_fixture, post_fixture, environment_fixture, culling_fixture, motion_fixture, dirty_fixture, workload_fixture
proc canvas(): JsObject {.importjs: "document.getElementById('scene')".}
proc legacy(): bool {.importjs: "(new URLSearchParams(location.search).has('webgl1'))".}
proc bytes(): JsObject {.importjs: "new Uint8Array(4)".}
proc item(a: JsObject; i: int): int {.importjs: "#[#]".}
proc frameBytes(): JsObject {.importjs: "new Uint8Array(16384)".}
proc ready() {.importjs: "(document.getElementById('status').textContent='PASS')".}
let device = acquire(canvas(),legacy())
let pixel = bytes()
runTerritoryProbe(device.ctx, device.caps, proc(x,y: int): array[4,uint8] =
  device.ctx.readPixels(x,y,1,1,0x1908,0x1401,pixel)
  for i in 0..3: result[i] = uint8(item(pixel,i)))
doAssert device.ctx.getError().to(int) == 0
let frame = frameBytes()
runInstanceProbe(device.ctx,device.caps,proc(): seq[uint8] =
  device.ctx.readPixels(0,0,64,64,0x1908,0x1401,frame)
  result = newSeq[uint8](64*64*4)
  for i in 0..<result.len: result[i] = uint8(item(frame,i)))
doAssert device.ctx.getError().to(int) == 0
runPostProbe(device.ctx,device.caps,proc(): seq[uint8] =
  device.ctx.readPixels(0,0,64,64,0x1908,0x1401,frame)
  result = newSeq[uint8](64*64*4)
  for i in 0..<result.len: result[i] = uint8(item(frame,i)))
doAssert device.ctx.getError().to(int) == 0
runEnvironmentProbe(device.ctx,device.caps,proc(): seq[uint8] =
  device.ctx.readPixels(0,0,64,64,0x1908,0x1401,frame)
  result = newSeq[uint8](64*64*4)
  for i in 0..<result.len: result[i] = uint8(item(frame,i)))
doAssert device.ctx.getError().to(int) == 0
runCullingProbe(device.ctx,device.caps,proc(): seq[uint8] =
  device.ctx.readPixels(0,0,64,64,0x1908,0x1401,frame)
  result = newSeq[uint8](64*64*4)
  for i in 0..<result.len: result[i] = uint8(item(frame,i)))
doAssert device.ctx.getError().to(int) == 0
runMotionProbe(device.ctx,device.caps,proc(): seq[uint8] =
  device.ctx.readPixels(0,0,64,64,0x1908,0x1401,frame)
  result = newSeq[uint8](64*64*4)
  for i in 0..<result.len: result[i] = uint8(item(frame,i)))
doAssert device.ctx.getError().to(int) == 0
runDirtyProbe(device.ctx,device.caps,proc(): seq[uint8] =
  device.ctx.readPixels(0,0,64,64,0x1908,0x1401,frame)
  result = newSeq[uint8](64*64*4)
  for i in 0..<result.len: result[i] = uint8(item(frame,i)))
doAssert device.ctx.getError().to(int) == 0
runCameraProbe(device.ctx,device.caps,proc(): seq[uint8] =
  device.ctx.readPixels(0,0,64,64,0x1908,0x1401,frame)
  result = newSeq[uint8](64*64*4)
  for i in 0..<result.len: result[i] = uint8(item(frame,i)))
doAssert device.ctx.getError().to(int) == 0
runWorkloadProbe(device.ctx,device.caps,proc(): seq[uint8] =
  device.ctx.readPixels(0,0,64,64,0x1908,0x1401,frame)
  result = newSeq[uint8](64*64*4)
  for i in 0..<result.len: result[i] = uint8(item(frame,i)))
doAssert device.ctx.getError().to(int) == 0
ready()
