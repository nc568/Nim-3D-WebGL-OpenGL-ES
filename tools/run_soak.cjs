// Standalone preset replay. Requires a built bundle served on 127.0.0.1:8080.
const engine=process.env.BROWSER_ENGINE||'chromium';
(async()=>{
 if(!['chromium','firefox','webkit'].includes(engine))throw Error('Unknown browser engine');
 if(process.env.SOAK_RECIPE_FILE) {
  if(process.env.SOAK_FRAMES||process.env.SOAK_CYCLES)throw Error('Unset SOAK_FRAMES/SOAK_CYCLES for recipe replay');
  const recipes=require('./soak_recipe.cjs');recipes.load(process.env.SOAK_RECIPE_FILE,recipes.identity());
 }
 let browser;
 try {
  if(engine==='chromium') {
   if(process.platform!=='linux')throw Error('Pinned Sparticuz Chromium runner requires Linux');
   const {default:chromium,inflate}=require('@sparticuz/chromium');
   if(process.env.USE_BUNDLED_LIBS==='1') {
    const dir=await inflate(require('path').join(__dirname,'../node_modules/@sparticuz/chromium/bin/al2023.tar.br'));
    process.env.LD_LIBRARY_PATH=dir+'/lib:'+(process.env.LD_LIBRARY_PATH||'');
   }
   browser=await require('puppeteer-core').launch({executablePath:await chromium.executablePath(),args:chromium.args,headless:true});
  } else {
   if(engine==='webkit'&&(process.platform!=='darwin'||process.arch!=='arm64'))throw Error('WebKit replay target is macOS ARM64');
   browser=await require('playwright')[engine].launch({headless:true,...(engine==='firefox'?{firefoxUserPrefs:{'webgl.force-enabled':true}}:{})});
  }
  await require('./soak_test.cjs')(browser,engine);
 } finally {if(browser)await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
