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
