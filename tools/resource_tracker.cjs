// Serializable into a test page; never installed by production code.
function installResourceTracker(gl) {
 const kinds=['Buffer','Texture','Program','Shader','Framebuffer','Renderbuffer','Query','VertexArray'];
 const entries=[],violations=[];
 for(const kind of kinds) {
  const create='create'+kind,remove='delete'+kind;
  if(typeof gl[create]!=='function'||typeof gl[remove]!=='function')continue;
  const originalCreate=gl[create],originalRemove=gl[remove],active=new Set();
  const entry={kind,active,created:0,deleted:0,peak:0,originalCreate,originalRemove,create,remove};
  gl[create]=function(...args) {
   const value=originalCreate.apply(this,args);
   if(value){active.add(value);entry.created++;entry.peak=Math.max(entry.peak,active.size);}
   return value;
  };
  gl[remove]=function(value) {
   // Mark only after successful callback; null deletes are legal no-ops.
   const result=originalRemove.call(this,value);
   if(value){if(!active.delete(value)){if(violations.length<16)violations.push('Unknown/duplicate '+kind);}else entry.deleted++;}
   return result;
  };
  entries.push(entry);
 }
 return {
  snapshot(){return {violations:[...violations],resources:entries.map(e=>({kind:e.kind,live:e.active.size,created:e.created,deleted:e.deleted,peak:e.peak}))};},
  restore(){for(const e of entries){gl[e.create]=e.originalCreate;gl[e.remove]=e.originalRemove;}}
 };
}
module.exports={installResourceTracker};
