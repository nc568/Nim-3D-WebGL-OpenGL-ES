## CPU reference for the documented nine-tap, display-referred FXAA variant.
## Coordinates are texel centers; sampling is bilinear with clamped edges.
import std/math

type RGB = array[3,float64]
func sample(image: seq[uint8]; x,y: float64): RGB =
  let cx = clamp(x,0.0,63.0)
  let cy = clamp(y,0.0,63.0)
  let ix = int(floor(cx))
  let iy = int(floor(cy))
  let fx = cx-float64(ix)
  let fy = cy-float64(iy)
  for c in 0..2:
    let a = float64(image[(iy*64+ix)*4+c])
    let b = float64(image[(iy*64+min(63,ix+1))*4+c])
    let d = float64(image[(min(63,iy+1)*64+ix)*4+c])
    let e = float64(image[(min(63,iy+1)*64+min(63,ix+1))*4+c])
    result[c] = ((a*(1-fx)+b*fx)*(1-fy)+(d*(1-fx)+e*fx)*fy)/255
func luminance(c: RGB): float64 = c[0]*0.299+c[1]*0.587+c[2]*0.114

proc checkFxaa*(source,filtered: seq[uint8]) =
  var changed = 0
  for y in 0..<64:
    for x in 0..<64:
      let xf = float64(x)
      let yf = float64(y)
      let center = sample(source,xf,yf)
      let nw = luminance(sample(source,xf-1,yf-1))
      let ne = luminance(sample(source,xf+1,yf-1))
      let sw = luminance(sample(source,xf-1,yf+1))
      let se = luminance(sample(source,xf+1,yf+1))
      let m = luminance(center)
      let lo = min(m,min(min(nw,ne),min(sw,se)))
      let hi = max(m,max(max(nw,ne),max(sw,se)))
      var expected = center
      if hi-lo >= max(0.03125,hi*0.125):
        var dx = -((nw+ne)-(sw+se))
        var dy = (nw+sw)-(ne+se)
        let reduce = max((nw+ne+sw+se)*0.25*0.03125,1.0/128)
        let denominator = min(abs(dx),abs(dy))+reduce
        dx = clamp(dx/denominator,-8.0,8.0)
        dy = clamp(dy/denominator,-8.0,8.0)
        let a0 = sample(source,xf-dx/6,yf-dy/6)
        let a1 = sample(source,xf+dx/6,yf+dy/6)
        let b0 = sample(source,xf-dx/2,yf-dy/2)
        let b1 = sample(source,xf+dx/2,yf+dy/2)
        var a,b: RGB
        for c in 0..2:
          a[c] = (a0[c]+a1[c])*0.5
          b[c] = a[c]*0.5+(b0[c]+b1[c])*0.25
        let lb = luminance(b)
        expected = if lb < lo or lb > hi: a else: b
      for c in 0..2:
        let index = (y*64+x)*4+c
        doAssert abs(int(round(expected[c]*255))-int(filtered[index])) <= 3,
          "FXAA differs from CPU bilinear/luminance reference"
        if abs(int(source[index])-int(filtered[index])) > 3: inc changed
      doAssert filtered[(y*64+x)*4+3] == 255
  doAssert changed > 20, "FXAA did not smooth the diagonal test edges"
