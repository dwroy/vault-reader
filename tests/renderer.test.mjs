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
test('localized reader chrome preserves mixed-language prose and code direction',()=>{
  const {dom,api,document}=page();
  const source='---\ntags: [test]\n---\n# English title\n\nنص عربي\n\n```js\nconst path = "a/b";\n```\n\n[[missing]]\n\n![[missing.png]]';
  api.setLocalization({language:'ar',properties:'الخصائص',notFound:'غير موجود',imageNotFound:'الصورة غير موجودة'});
  api.render(source,'README.md');
  assert.equal(document.documentElement.lang,'ar');
  assert.equal(document.querySelector('.properties summary').textContent,'الخصائص');
  assert.equal(document.querySelector('.properties summary').dir,'rtl');
  assert.equal(document.querySelector('h1').textContent,'English title');
  assert.equal(document.querySelector('h1').dir,'auto');
  assert.equal(document.querySelector('pre code').dir,'ltr');
  assert.match(document.querySelector('.dead-link').title,/غير موجود/);
  api.setLocalization({language:'en',properties:'<img src=x onerror=alert(1)>'});
  api.render(source,'README.md');
  assert.equal(document.querySelector('.properties summary').textContent,'<img src=x onerror=alert(1)>');
  assert.equal(document.querySelector('.properties summary img'),null);
  assert.equal(document.querySelector('h1').textContent,'English title');
  dom.window.close();
});
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

test('search highlights span inline formatting, preserve spelling and never search URL attributes',()=>{
  const {dom,api,document,messages}=page();
  api.setTree([{path:'child.md',type:'blob'}]);
  api.render('---\nsecret: hidden-property\n---\n# Search\n\n我们在**公园**散步。 CAFÉ café\n\n[[child|孩子]] [Visible](https://example.invalid/hidden-url)\n\n`literal-code`','search.md');
  const before=document.getElementById('content').textContent;
  assert.equal(api.highlightSearch(['公园散步','cafe','孩子']),4);
  assert.equal([...document.querySelectorAll('mark.search-hit')].map(x=>x.textContent).join('|'),'公园|散步|CAFÉ|café|孩子');
  assert.equal(document.getElementById('content').textContent,before);
  document.querySelector('a').click();assert.equal(messages.at(-1).body.href,'vault://f/child.md');
  assert.equal(api.highlightSearch(['hidden-property','hidden-url','<img src=x onerror=alert(1)>']),0);
  assert.equal(document.querySelectorAll('mark.search-hit').length,0);
  assert.equal(api.highlightSearch(['literal-code']),1);
  assert.equal(api.highlightSearch(['literal-code']),1);
  assert.equal(document.querySelectorAll('mark mark').length,0);
  assert.equal(api.highlightSearch([]),0);
  assert.equal(document.getElementById('content').textContent,before);
  dom.window.close();
});
test('search opens collapsed content and its position survives the delayed initial scroll',async()=>{
  const {dom,api,document}=page();let y=0;
  Object.defineProperty(dom.window,'scrollY',{get:()=>y,configurable:true});
  Object.defineProperty(dom.window,'innerHeight',{value:800,configurable:true});
  dom.window.scrollTo=(_x,next)=>{y=next};
  api.render('# Search\n\n<details><summary>More</summary><p>目标文字</p></details>','search.md');
  assert.equal(api.highlightSearch(['目标']),1);
  document.querySelector('mark.search-hit').getBoundingClientRect=()=>({top:1800-y});
  assert.equal(api.scrollToSearchMatch(),true);
  assert.equal(document.querySelector('details').open,true);
  assert.equal(y,1600);
  await new Promise(resolve=>setTimeout(resolve,60));assert.equal(y,1600);
  api.highlightSearch(['不存在']);assert.equal(api.scrollToSearchMatch(),false);assert.equal(y,1600);
  dom.window.close();
});
