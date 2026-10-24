## GL-family post shaders, deliberately only GLSL 300 ES (T1 path).
const PostVertex* = """#version 300 es
in vec3 aPosition;
out highp vec2 vUv;
void main() {
  vUv = aPosition.xy*0.5+0.5;
  gl_Position = vec4(aPosition,1.0);
}
"""

const PostFragment* = """#version 300 es
precision highp float;
in highp vec2 vUv;
out vec4 fragColor;
uniform sampler2D uScene;
uniform vec2 uInvSize;
uniform bool uFxaa;
uniform bool uDither;
uniform float uExposure;
uniform float uVignette;
float luma(vec3 c) { return dot(c,vec3(0.299,0.587,0.114)); }
vec3 filtered() {
  vec3 center = texture(uScene,vUv).rgb;
  if (!uFxaa) return center;
  float nw = luma(texture(uScene,vUv+vec2(-1.0,-1.0)*uInvSize).rgb);
  float ne = luma(texture(uScene,vUv+vec2( 1.0,-1.0)*uInvSize).rgb);
  float sw = luma(texture(uScene,vUv+vec2(-1.0, 1.0)*uInvSize).rgb);
  float se = luma(texture(uScene,vUv+vec2( 1.0, 1.0)*uInvSize).rgb);
  float m = luma(center);
  float low = min(m,min(min(nw,ne),min(sw,se)));
  float high = max(m,max(max(nw,ne),max(sw,se)));
  if (high-low < max(0.03125,high*0.125)) return center;
  vec2 dir = vec2(-((nw+ne)-(sw+se)),(nw+sw)-(ne+se));
  float reduce = max((nw+ne+sw+se)*0.25*0.03125,1.0/128.0);
  dir = clamp(dir/(min(abs(dir.x),abs(dir.y))+reduce),vec2(-8.0),vec2(8.0))*uInvSize;
  vec3 a = 0.5*(texture(uScene,vUv+dir*(1.0/3.0-0.5)).rgb+
                texture(uScene,vUv+dir*(2.0/3.0-0.5)).rgb);
  vec3 b = a*0.5+0.25*(texture(uScene,vUv-dir*0.5).rgb+texture(uScene,vUv+dir*0.5).rgb);
  float lb = luma(b);
  return (lb<low || lb>high) ? a : b;
}
vec3 decodeSrgb(vec3 c) {
  return mix(c/12.92,pow((c+0.055)/1.055,vec3(2.4)),step(vec3(0.04045),c));
}
vec3 encodeSrgb(vec3 c) {
  c = max(c,vec3(0.0));
  return mix(c*12.92,1.055*pow(c,vec3(1.0/2.4))-0.055,step(vec3(0.0031308),c));
}
float noise(vec2 p) {
  return fract(52.9829189*fract(dot(p,vec2(0.06711056,0.00583715))));
}
void main() {
  vec3 color = filtered(); // already sRGB-encoded, NOT linear light
  if (uExposure != 1.0 || uVignette != 0.0) {
    vec2 q = vUv*2.0-1.0;
    float shade = 1.0-uVignette*smoothstep(0.2,1.8,dot(q,q));
    color = encodeSrgb(decodeSrgb(color)*uExposure*shade);
  }
  if (uDither) color += vec3((noise(gl_FragCoord.xy)-noise(gl_FragCoord.yx+17.0))/255.0);
  fragColor = vec4(color,1.0);
}
"""
