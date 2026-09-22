import test from 'node:test';
import assert from 'node:assert/strict';
import { createTree, normalize, headingID } from '../packages/reader-web/src/tree.js';
const entries = ['README.md','生活/日记.md','阅读/日记.md','日记.md','a/深层/日记.md','b/note.md','a/note.md','files/照片 1.png'].map(path => ({path,type:'blob'}));
const tree = createTree(entries);
test('same-directory, depth and lexical ambiguity ordering', () => {
  assert.equal(tree.resolve('日记','生活/索引.md').path,'生活/日记.md');
  assert.equal(tree.resolve('日记','其他/索引.md').path,'日记.md');
  assert.equal(tree.resolve('note','其他/索引.md').path,'a/note.md');
});
test('path-qualified links, extensions, URI decoding, anchors and missing links', () => {
  assert.equal(tree.resolve('生活/日记','README.md').path,'生活/日记.md');
  assert.equal(tree.resolve('%E7%94%9F%E6%B4%BB/%E6%97%A5%E8%AE%B0.md# A  B ','README.md').anchor,' A  B');
  assert.equal(tree.resolve('#标题','README.md').path,'README.md');
  assert.equal(tree.resolve('照片%201.png','README.md').path,'files/照片 1.png');
  assert.equal(tree.resolve('missing','README.md').path,null);
  assert.doesNotThrow(() => tree.resolve('%bad%','README.md'));
});
test('relative paths remain inside the vault', () => {
  assert.equal(tree.relative('../files/照片%201.png','生活/日记.md').path,'files/照片 1.png');
  assert.equal(tree.relative('../../README.md','生活/日记.md').path,null);
  assert.equal(tree.relative('../README.md#标题','生活/日记.md').anchor,'标题');
  assert.equal(normalize('../../secret'),null);
  assert.equal(headingID('  Hello   World  '),'hello world');
});
