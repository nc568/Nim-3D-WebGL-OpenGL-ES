## Actual WebGL calls and buffer contents, not a wall-clock speed assertion.
import std/jsffi
import softgfx/backends/web
import softgfx/[types, instances]

proc track(gl: Context; capacity: int) {.importjs: """(function(g,n){
 const upload=g.bufferSubData,sub=Float32Array.prototype.subarray;
 const t=g._uploadProbe={calls:0,views:0,args:null,expected:new Float32Array(n*9)};
 Float32Array.prototype.subarray=function(...a){t.views++;return sub.apply(this,a);};
 g.bufferSubData=function(...a){t.calls++;t.args=a;return upload.apply(this,a);};
 t.restore=()=>{g.bufferSubData=upload;Float32Array.prototype.subarray=sub;delete g._uploadProbe;};
})(#,#)""".}
proc restore(gl: Context) {.importjs: "#._uploadProbe.restore()".}
proc views(gl: Context): int {.importjs: "#._uploadProbe.views".}
proc calls(gl: Context): int {.importjs: "#._uploadProbe.calls".}
proc check(gl: Context; modern: bool; first,count: int; source: seq[float32]) {.importjs: """(function(g,modern,first,count,source){
 const t=g._uploadProbe,a=t.args,offset=modern?a[3]:0;
 if(a.length!==(modern?5:3)||a[0]!==g.ARRAY_BUFFER||a[1]!==first*36||!(a[2] instanceof Float32Array))throw Error('upload overload/offset/type');
 if(modern&&(a[3]!==first*9||a[4]!==count*9))throw Error('source element units');
 if(!modern&&a[2].length!==count*9)throw Error('legacy view length');
 if(modern&&source instanceof Float32Array&&a[2]!==source)throw Error('direct source identity');
 for(let i=0;i<count*9;i++){
  const value=Math.fround(source[first*9+i]);
  if(a[2][offset+i]!==value)throw Error('wrong source range');
  t.expected[first*9+i]=value;
 }
 if(modern){
  const actual=new Float32Array(t.expected.length);
  g.getBufferSubData(g.ARRAY_BUFFER,0,actual);
  if(!actual.every((v,i)=>v===t.expected[i]))throw Error('GPU buffer range/sentinel mismatch');
 }
 if(g.getError())throw Error('range upload GL error');
})(#,#,#,#,#)""".}

proc runUploadRangeProbe*(gl: Context; caps: Capabilities) =
  const capacity = 16
  for fallback in [false,true]:
    var stream = gl.createInstanceStream(caps.api,capacity,fallback)
    track(gl,capacity)
    try:
      var direct = newInstanceData(capacity)
      var replacement = newInstanceData(capacity)
      var ordinary = newSeq[float32](capacity*InstanceFloats)
      for i in 0..<direct.len:
        direct[i] = float32(i+1)
        replacement[i] = float32(i+1001)
        ordinary[i] = float32(i+2001)
      if stream.mode == fallbackDraws:
        gl.uploadInstancesRange(stream,direct,2,3)
        doAssert calls(gl) == 0 and views(gl) == 0
      else:
        let modern = caps.api == webgl2
        gl.uploadInstances(stream,direct,capacity)
        check(gl,modern,0,capacity,direct)
        for tick in 0..<128:
          let count = 1+tick mod 4
          let first = tick mod (capacity-count+1)
          direct[first*InstanceFloats] = float32(tick+4001)
          gl.uploadInstancesRange(stream,direct,first,count)
          check(gl,modern,first,count,direct)
          let before = views(gl)
          gl.uploadInstancesRange(stream,direct,first,count)
          check(gl,modern,first,count,direct)
          doAssert views(gl) == before # repeated WebGL1 ranges reuse their view
        # Same range with a new backing, then compatibility storage, then direct.
        gl.uploadInstancesRange(stream,replacement,7,2)
        check(gl,modern,7,2,replacement)
        gl.uploadInstancesRange(stream,ordinary,7,2)
        check(gl,modern,7,2,ordinary)
        ordinary[7*InstanceFloats] = 9001
        gl.uploadInstancesRange(stream,ordinary,7,2)
        check(gl,modern,7,2,ordinary)
        gl.uploadInstancesRange(stream,direct,7,2)
        check(gl,modern,7,2,direct)
        let before = calls(gl)
        gl.uploadInstancesRange(stream,direct,capacity,0)
        doAssert calls(gl) == before # WebGL2 zero length means remainder: never submit
        if modern: doAssert views(gl) == 0
        else: doAssert views(gl) > 0
        echo "UPLOAD_RANGE api=",caps.api," calls=",calls(gl)," views=",views(gl)," PASS"
    finally:
      restore(gl)
      gl.destroyInstanceStream(stream)
