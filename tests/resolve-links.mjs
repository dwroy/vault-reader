import { execFileSync } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import MarkdownIt from 'markdown-it';
import { createTree } from '../packages/reader-web/src/tree.js';
const root = path.resolve(process.argv[2] || '');
if (!process.argv[2]) { console.error('Usage: node tests/resolve-links.mjs /path/to/vault [--summary]'); process.exit(1); }
// Git-tracked files only: untracked private folders never enter the report or app fixtures.
const paths = execFileSync('git',['-C',root,'ls-files','-z'],{encoding:'utf8'}).split('\0').filter(Boolean);
const tree = createTree(paths.map(path => ({path,type:'blob'}))), md = new MarkdownIt();
const dead = {}, ambiguous = [];
let total=0, resolved=0;
for (const file of paths.filter(p => /\.md$/i.test(p))) {
  let source = await readFile(path.join(root,file),'utf8');
  source=source.replace(/^---\r?\n[\s\S]*?\r?\n---(?:\r?\n|$)/,'').replace(/%%[\s\S]*?%%/g,'');
  // Count only prose, excluding fenced/indented code and inline code examples.
  for (const block of md.parse(source,{}).filter(t=>t.type==='inline')) {
    const text=(block.children||[]).filter(t=>t.type==='text').map(t=>t.content).join('');
    for(const match of text.matchAll(/!?\[\[([^\]\n]+)\]\]/g)) {
      const target=match[1].split('|')[0], result=tree.resolve(target,file); total++;
      if(result.path) resolved++; else (dead[file] ||= []).push(target);
      if(result.candidates.length>1) ambiguous.push({from:file,target,selected:result.path,candidates:result.candidates});
    }
  }
}
const duplicateNames=[...tree.mdByName].filter(([,paths])=>paths.length>1).map(([name,paths])=>({name,paths}));
const summary={trackedFiles:paths.length,markdown:paths.filter(p=>/\.md$/i.test(p)).length,total,resolved,unresolved:total-resolved,duplicateNameGroups:duplicateNames.length,ambiguousLinks:ambiguous.length};
console.log(JSON.stringify(process.argv.includes('--summary')?summary:{summary,dead,ambiguous,duplicateNames},null,2));
