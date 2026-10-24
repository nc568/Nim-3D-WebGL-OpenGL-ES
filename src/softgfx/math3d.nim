## Right-handed world, Y up, camera looks down -Z. Column-major GL matrices.
## Angles are radians; clip depth is [-1, 1] on both WebGL and GLES.
import std/math

type
  Vec3* = array[3, float32]
  Mat4* = array[16, float32]
  Camera* = object
    eye*, target*, up*: Vec3
    fovY*, nearPlane*, farPlane*: float32

func finite*(x: float32): bool = classify(x) notin {fcNan, fcInf, fcNegInf}
func finite*(v: Vec3): bool = finite(v[0]) and finite(v[1]) and finite(v[2])
func `+`*(a, b: Vec3): Vec3 = [a[0]+b[0], a[1]+b[1], a[2]+b[2]]
func `-`*(a, b: Vec3): Vec3 = [a[0]-b[0], a[1]-b[1], a[2]-b[2]]
func `*`*(a: Vec3; s: float32): Vec3 = [a[0]*s, a[1]*s, a[2]*s]
func dot*(a, b: Vec3): float32 = a[0]*b[0]+a[1]*b[1]+a[2]*b[2]
func cross*(a, b: Vec3): Vec3 =
  [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]
func normalized*(v: Vec3): Vec3 =
  let length = sqrt(dot(v, v))
  if not finite(v) or not finite(length) or length < 1e-6:
    raise newException(ValueError, "Degenerate direction")
  v * (1'f32/length)

func identity*(): Mat4 =
  result[0] = 1
  result[5] = 1
  result[10] = 1
  result[15] = 1

func `*`*(a, b: Mat4): Mat4 =
  for col in 0..3:
    for row in 0..3:
      for k in 0..3:
        result[col*4+row] += a[k*4+row] * b[col*4+k]

func transform*(m: Mat4; v: array[4, float32]): array[4, float32] =
  for row in 0..3:
    for col in 0..3:
      result[row] += m[col*4+row] * v[col]

func perspective*(fovY, aspect, nearPlane, farPlane: float32): Mat4 =
  if not finite(fovY) or not finite(aspect) or not finite(nearPlane) or
      not finite(farPlane) or fovY <= 0 or fovY >= PI.float32 or
      aspect <= 0 or nearPlane <= 0 or farPlane <= nearPlane:
    raise newException(ValueError, "Invalid perspective frustum")
  let f = 1'f32 / tan(fovY * 0.5'f32)
  result[0] = f/aspect
  result[5] = f
  result[10] = (farPlane+nearPlane)/(nearPlane-farPlane)
  result[11] = -1
  result[14] = (2*farPlane*nearPlane)/(nearPlane-farPlane)

func lookAt*(eye, target, up: Vec3): Mat4 =
  if not finite(eye) or not finite(target):
    raise newException(ValueError, "Non-finite camera")
  let z = normalized(eye-target)
  let x = normalized(cross(up, z))
  let y = cross(z, x)
  result = identity()
  for i in 0..2:
    result[i*4] = x[i]
    result[i*4+1] = y[i]
    result[i*4+2] = z[i]
  result[12] = -dot(x, eye)
  result[13] = -dot(y, eye)
  result[14] = -dot(z, eye)

func viewProjection*(c: Camera; aspect: float32): Mat4 =
  perspective(c.fovY, aspect, c.nearPlane, c.farPlane) * lookAt(c.eye, c.target, c.up)
