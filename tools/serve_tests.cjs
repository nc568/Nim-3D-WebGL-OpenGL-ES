// Small portable CI server; same generated files on Linux and macOS.
const http=require('http'), fs=require('fs'), path=require('path');
const root=path.resolve('build');
http.createServer((req,res)=>{
 let file;
 try { file=path.resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://test').pathname)); }
 catch {res.writeHead(400).end(); return;}
 if(file!==root && !file.startsWith(root+path.sep)){res.writeHead(403).end();return;}
 if(file===root) file=path.join(root,'index.html');
 fs.readFile(file,(error,data)=>{
  if(error){res.writeHead(404).end();return;}
  res.setHeader('Content-Type',file.endsWith('.js')?'application/javascript':file.endsWith('.html')?'text/html':'application/octet-stream');
  res.end(data);
 });
}).listen(8080,'0.0.0.0',()=>console.log('Test server ready on 8080'));
