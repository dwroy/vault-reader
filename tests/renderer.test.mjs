import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';
const bundle=readFileSync('VaultReader/Resources/renderer/vendor/renderer.bundle.js','utf8');
function page(base='vault://file/') {
  const dom=new JSDOM('<main id="content"></main>',{url:'https://reader.test/',runScripts:'outside-only',pretendToBeVisual:true});
  const messages=[];
  dom.window.scrollTo=()=>{};
  dom.window.VaultHost={resourceBaseURL:base,postMessage:(type,body)=>messages.push({type,body})};
  dom.window.eval(bundle);
  return {dom,api:dom.window.VaultReader,document:dom.window.document,messages};
}
test('same bundle supports both iOS scheme and Android HTTPS resource hosts',()=>{
  for(const base of ['vault://file/','https://appassets.androidplatform.net/vault/files/']) {
    const {dom,api,document,messages}=page(base);
    api.setTree([{path:'note.md',type:'blob'},{path:'files/图.svg',type:'blob'}]);
    api.render('# 标题\n[[note|别名]]\n![[files/图.svg|300]]','README.md',1,'light');
    const image=document.querySelector('img');
    assert.equal(image.getAttribute('src'),base+'files/%E5%9B%BE.svg');
    image.click();assert.deepEqual(JSON.parse(JSON.stringify(messages.at(-1))),{type:'preview',body:{path:'files/图.svg'}});
    document.querySelector('a').click();assert.equal(messages.at(-1).body.href,'vault://f/note.md');
    dom.window.close();
  }
});
test('sanitize untrusted HTML, keep code literal, and resolve new tree entries',()=>{
  const {dom,api,document}=page();
  api.setTree([]);
  const source='[[new]]\n<script>alert(1)</script><img src="javascript:x" onerror="x"><iframe></iframe>\n\n`%%literal%%`';
  api.render(source,'README.md',1,'light');
  assert.equal(document.querySelectorAll('#content script,#content iframe,[onerror]').length,0);
  assert.equal(document.querySelector('code').textContent,'%%literal%%');
  assert.equal(document.querySelectorAll('.dead-link').length,1);
  api.setTree([{path:'new.md',type:'blob'}]);api.render(source,'README.md',1,'light');
  assert.equal(document.querySelector('a').getAttribute('href'),'vault://f/new.md');
  dom.window.close();
});

test('reading v2 resumes within a heading after reflow and distinguishes duplicate headings',()=>{
  const {dom,api,document}=page();
  let y=0, height=2000, positions=[100,600,1200];
  Object.defineProperty(dom.window,'scrollY',{get:()=>y,configurable:true});
  Object.defineProperty(dom.window,'innerHeight',{value:500,configurable:true});
  Object.defineProperty(document.documentElement,'scrollHeight',{get:()=>height,configurable:true});
  dom.window.scrollTo=(_x,next)=>{y=next};
  api.render('# Book\n\n## Repeated\n\nText\n\n## Repeated\n\nEnd','read/book.md');
  [...document.querySelectorAll('h1,h2')].forEach((element,i)=>element.getBoundingClientRect=()=>({top:positions[i]-y}));
  assert.equal(api.version,2);
  assert.deepEqual(Array.from(api.outline(),x=>x.id),['book::0','repeated::0','repeated::1']);
  y=900;
  const position=api.capturePosition();
  assert.equal(position.heading,'repeated::0');assert.equal(position.withinHeading,0.5);
  positions=[100,800,1600];height=2500;
  api.restorePosition(position);assert.equal(y,1200);
  api.scrollToSection('repeated::1');assert.equal(y,1600);
  api.restorePosition({heading:'removed',fraction:0.5});assert.equal(y,1000);
  api.restorePosition({fraction:Infinity,withinHeading:NaN});assert.equal(y,0);
  dom.window.close();
});
test('reading outline ignores fenced code and uses the shared sanitizer',()=>{
  const {dom,api,document}=page();
  api.render('# A\n\n```md\n## fake\n```\n\n## **Real**\n\n<script>bad()</script>','read/a.md',1,'sepia');
  api.setReadingMode(true);
  assert.deepEqual(Array.from(api.outline(),x=>x.title),['A','Real']);
  assert.equal(document.documentElement.dataset.theme,'sepia');
  assert.equal(document.documentElement.dataset.reading,'book');
  assert.equal(document.querySelectorAll('#content script').length,0);
  dom.window.close();
});
test('book restoration is not overwritten by a delayed first animation frame',async()=>{
  const {dom,api,document}=page(); let y=0;
  Object.defineProperty(dom.window,'scrollY',{get:()=>y,configurable:true});
  Object.defineProperty(dom.window,'innerHeight',{value:500,configurable:true});
  Object.defineProperty(document.documentElement,'scrollHeight',{value:2000,configurable:true});
  dom.window.scrollTo=(_x,next)=>{y=next};
  api.setReadingMode(true);api.render('# Book\n\n## Next','read/book.md');
  [...document.querySelectorAll('h1,h2')].forEach((element,i)=>element.getBoundingClientRect=()=>({top:[100,700][i]-y}));
  api.restorePosition({heading:'next::0',withinHeading:0,fraction:0.5});
  await new Promise(resolve=>setTimeout(resolve,60));
  assert.equal(y,700);
  dom.window.close();
});
