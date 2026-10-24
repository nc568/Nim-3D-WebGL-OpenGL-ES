import std/math
import softgfx/[instances, environment]

var poses = @[instance([1'f32,2,3],yaw=0.3,scale=0.1)]
var data = newSeq[float32](InstanceFloats)
doAssert packInstancesChanged(poses,data)
doAssert not packInstancesChanged(poses,data)
var forced = newSeq[float32](InstanceFloats)
packInstances(poses,forced)
doAssert data == forced
# Nim JS scalars can retain doubles: changes below GPU float32 precision are no-op.
let tinyOffset = float32(pow(10.0,-10.0))
poses[0].scale += tinyOffset
doAssert not packInstancesChanged(poses,data)
poses[0].position[0] += 0.5
doAssert packInstancesChanged(poses,data)
doAssert not packVisibleChanged(poses,[0],1,data)
let originalX = data[0]
var rejected = false
try: discard packVisibleChanged(poses,[0,0],2,data)
except ValueError: rejected = true
doAssert rejected and data[0] == originalX
var pair = @[instance([99'f32,0,0]),instance(scale=0)]
var two = newSeq[float32](2*InstanceFloats)
two[0] = 42
rejected = false
try: discard packInstancesChanged(pair,two)
except ValueError: rejected = true
doAssert rejected and two[0] == 42

var cached, settings: SceneEffects
var delta: EffectChanges
doAssert not effectChanges(cached,settings,delta)
settings.eye[0] = NaN.float32 # ignored while disabled
settings.blobs[0].strength = NaN.float32
settings.validate()
doAssert not effectChanges(cached,settings,delta)
settings = SceneEffects(fogEnabled:true,fogNear:1,fogFar:20,eye:[1'f32,2,3],fogColor:[0.2'f32,0.3,0.4])
settings.validate()
doAssert effectChanges(cached,settings,delta)
doAssert delta.parameters and delta.eye and delta.color
retainEffects(settings,cached)
doAssert not effectChanges(cached,settings,delta)
settings.eye[1] += 1
doAssert effectChanges(cached,settings,delta)
doAssert delta.eye and not delta.parameters and not delta.color
retainEffects(settings,cached)
settings.blobCount = 1
settings.blobs[0] = BlobShadow(radiusX:1,radiusZ:2,strength:0.4)
doAssert effectChanges(cached,settings,delta)
doAssert delta.parameters and delta.blobs[0] and not delta.blobs[1]
retainEffects(settings,cached)
settings.blobs[0].center[0] = 2
doAssert effectChanges(cached,settings,delta)
doAssert delta.blobs[0] and not delta.parameters and not delta.eye
retainEffects(settings,cached)
settings = SceneEffects()
doAssert effectChanges(cached,settings,delta)
doAssert delta.parameters and delta.eye and delta.color and delta.blobs[0]
retainEffects(settings,cached)
doAssert cached.blobs[0].radiusX == 0 and cached.eye[0] == 0
doAssert not effectChanges(cached,settings,delta)
doAssert effectChanges(cached,settings,delta,force=true)
for i in 0..<MaxBlobs: doAssert delta.blobs[i]
echo "dirty packing / GPU float32 equality / effect groups / canonical reset: PASS"
