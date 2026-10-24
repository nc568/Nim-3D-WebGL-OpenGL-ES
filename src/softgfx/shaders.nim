import types

proc vertexSource*(api: Api): string =
  let modern = api in {webgl2, gles3}
  result = if modern: "#version 300 es\nin" else: "attribute"
  result.add """ vec3 aPosition;
"""
  let attr = if modern: "in" else: "attribute"
  let varying = if modern: "out" else: "varying"
  result.add attr & " vec3 aInstancePosition;\n" & attr & " vec3 aInstanceRotationScale;\n" & attr & " vec3 aInstanceTint;\n"
  result.add attr & " vec3 aTerritory;\n"
  result.add attr & " vec3 aNormal;\n" & attr & " vec3 aColor;\n"
  result.add varying & " mediump vec3 vWorld;\n" & varying & " mediump float vFog;\n"
  result.add varying & " vec3 vTerritory;\n"
  result.add varying & " vec3 vNormal;\n" & varying & " vec3 vColor;\n"
  result.add """
uniform mat4 uViewProjection;
uniform mediump vec4 uFog;
uniform vec4 uEye;
void main() {
  vTerritory = aTerritory;
  float c = aInstanceRotationScale.x;
  float s = aInstanceRotationScale.y;
  vec3 position = vec3(c*aPosition.x+s*aPosition.z, aPosition.y, -s*aPosition.x+c*aPosition.z);
  position = position*aInstanceRotationScale.z+aInstancePosition;
  vWorld = position;
  vFog = 0.0;
  if (uFog.y > 0.0) vFog = clamp((length(position-uEye.xyz)-uFog.x)*uFog.y,0.0,1.0);
  vNormal = vec3(c*aNormal.x+s*aNormal.z, aNormal.y, -s*aNormal.x+c*aNormal.z);
  vColor = aColor*aInstanceTint;
  gl_Position = uViewProjection * vec4(position, 1.0);
}
"""

proc fragmentSource*(api: Api; unlit = false): string =
  let modern = api in {webgl2, gles3}
  result = if modern: "#version 300 es\n" else: ""
  result.add "precision mediump float;\n"
  let varying = if modern: "in" else: "varying"
  result.add varying & " mediump vec3 vWorld;\n" & varying & " mediump float vFog;\n"
  result.add varying & " vec3 vTerritory;\n"
  result.add varying & " vec3 vNormal;\n" & varying & " vec3 vColor;\n"
  result.add "uniform sampler2D uOwners;\nuniform sampler2D uPalette;\n"
  result.add "uniform mediump vec4 uFog;\nuniform vec4 uFogColor;\nuniform vec4 uBlobRects[4];\nuniform vec4 uBlobPlanes[4];\n"
  if modern: result.add "out vec4 fragColor;\n"
  result.add """
vec3 srgb(vec3 c) {
  c = max(c, vec3(0.0));
  return mix(12.92*c, 1.055*pow(c, vec3(1.0/2.4))-0.055,
             step(vec3(0.0031308), c));
}
float noise(vec2 p) {
  return fract(52.9829189 * fract(dot(p, vec2(0.06711056,0.00583715))));
}
void main() {
"""
  let sample = if modern: "texture" else: "texture2D"
  result.add "  float owner = floor(" & sample & "(uOwners, vTerritory.xy).r * 255.0 + 0.5);\n"
  result.add "  vec3 baseColor = mix(vColor, " & sample & "(uPalette, vec2((owner+0.5)/256.0,0.5)).rgb, clamp(vTerritory.z,0.0,1.0));\n"
  if modern and not unlit:
    result.add """
  vec3 n = normalize(vNormal);
  float light = smoothstep(0.0, 1.0, (dot(n, normalize(vec3(0.4,0.8,0.5)))+0.45)/1.45);
  vec3 ambient = mix(vec3(0.18,0.16,0.22),vec3(0.35,0.43,0.55),n.y*0.5+0.5);
  vec3 linearColor = baseColor * (ambient + vec3(0.8,0.65,0.45)*light);
"""
  else:
    result.add "  vec3 linearColor = baseColor; // T0: baked lighting only\n"
  result.add """
  // Analytic ellipses on horizontal receiver planes: no alpha/depth decal pass.
  for (int i=0; i<4; i++) {
    if (float(i) < uFog.z && vNormal.y > 0.5 && abs(vWorld.y-uBlobPlanes[i].x) < 0.04) {
      vec2 delta = vWorld.xz-uBlobRects[i].xy;
      float c = uBlobPlanes[i].z, s = uBlobPlanes[i].w;
      vec2 uv = vec2(c*delta.x-s*delta.y,s*delta.x+c*delta.y)/uBlobRects[i].zw;
      if (abs(uv.x) < 1.0 && abs(uv.y) < 1.0) {
        float shade = 1.0-uBlobPlanes[i].y*(1.0-smoothstep(0.15,1.0,dot(uv,uv)));
        linearColor *= shade;
      }
    }
  }
  linearColor = mix(linearColor,uFogColor.rgb,vFog);
  vec3 color = srgb(linearColor);
"""
  result.add "  color += vec3((noise(gl_FragCoord.xy)-noise(gl_FragCoord.yx+17.0))/255.0);\n"
  result.add (if modern: "  fragColor" else: "  gl_FragColor") & " = vec4(color,1.0);\n}\n"

proc skyVertexSource*(api: Api): string =
  let modern = api in {webgl2,gles3}
  result = if modern: "#version 300 es\n" else: ""
  let attr = if modern: "in" else: "attribute"
  let varying = if modern: "out" else: "varying"
  result.add attr & " vec3 aPosition;\n" & attr & " vec3 aColor;\n"
  result.add varying & " mediump vec3 vColor;\n"
  result.add "void main() { vColor=aColor; gl_Position=vec4(aPosition,1.0); }\n"

proc skyFragmentSource*(api: Api): string =
  ## Dedicated background shader: no owner/palette texture reads or blob loop.
  let modern = api in {webgl2,gles3}
  result = if modern: "#version 300 es\n" else: ""
  result.add "precision mediump float;\n"
  result.add (if modern: "in" else: "varying") & " mediump vec3 vColor;\n"
  if modern: result.add "out vec4 fragColor;\n"
  result.add """
float noise(vec2 p) {
  return fract(52.9829189 * fract(dot(p,vec2(0.06711056,0.00583715))));
}
void main() {
  vec3 c = max(vColor,vec3(0.0));
  vec3 color = mix(12.92*c,1.055*pow(c,vec3(1.0/2.4))-0.055,step(vec3(0.0031308),c));
  color += vec3((noise(gl_FragCoord.xy)-noise(gl_FragCoord.yx+17.0))/255.0);
"""
  result.add (if modern: "fragColor" else: "gl_FragColor") & "=vec4(color,1.0);\n}\n"
