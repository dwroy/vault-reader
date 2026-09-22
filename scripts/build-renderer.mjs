import { build } from 'esbuild';
import { copyFile, cp, mkdir, readFile, writeFile } from 'node:fs/promises';
const out = process.argv[2] || 'VaultReader/Resources/renderer';
await mkdir(out + '/vendor', {recursive:true});
await build({entryPoints:['packages/reader-web/src/renderer.js'], bundle:true, format:'iife', minify:true, legalComments:'eof', outfile:out+'/vendor/renderer.bundle.js', target:['safari18','chrome110']});
for (const name of ['index.html','style.css']) await copyFile('packages/reader-web/src/'+name, out+'/'+name);
await cp('node_modules/@fontsource-variable/noto-sans-sc/files',out+'/vendor/fonts',{recursive:true});
const fontCSS=(await readFile('node_modules/@fontsource-variable/noto-sans-sc/index.css','utf8')).replaceAll('./files/','./fonts/');
await writeFile(out+'/vendor/fonts.css',fontCSS);
const deps=['@fontsource-variable/noto-sans-sc','markdown-it','dompurify','markdown-it-footnote','markdown-it-task-lists','entities','linkify-it','mdurl','punycode.js','uc.micro'];
let notices='';
for (const dep of deps) {
 const p=JSON.parse(await readFile('node_modules/'+dep+'/package.json','utf8'));
 let license='';
 for (const name of ['LICENSE','LICENSE.md','LICENSE.txt','LICENSE-MIT.txt']) { try { license=await readFile('node_modules/'+dep+'/'+name,'utf8'); break; } catch {} }
 if(!license) throw new Error('Missing license for '+dep);
 notices+='\n## '+dep+' '+p.version+'\n'+license+'\n';
}
await writeFile(out+'/vendor/THIRD-PARTY-NOTICES.txt',notices.trim()+'\n');
