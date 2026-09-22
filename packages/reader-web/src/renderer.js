import MarkdownIt from 'markdown-it';
import DOMPurify from 'dompurify';
import footnote from 'markdown-it-footnote';
import taskLists from 'markdown-it-task-lists';
import { createTree, encodePath, headingID } from './tree.js';

const resourceURL = path => (window.VaultHost?.resourceBaseURL || 'vault://file/') + encodePath(path);
let tree = createTree([]), currentPath = '', lastContent = '', lastPath = '';
const md = new MarkdownIt({ html: true, linkify: false, typographer: false }).use(footnote).use(taskLists, { enabled: false });
const escape = md.utils.escapeHtml;
function fileURL(path, anchor = '') { return `vault://f/${encodePath(path)}${anchor ? '#' + encodeURIComponent(headingID(anchor)) : ''}`; }
function emit(name, body) { window.VaultHost?.postMessage(name, body); }
function wikiHTML(target, label, embed) {
  const result = tree.resolve(target, currentPath);
  if (!result.path) return `<span class="dead-link" title="未找到：${escape(target)}">${escape(label || target)}</span>`;
  const path = result.path;
  if (embed && /\.(png|jpe?g|gif|webp|svg|heic|avif)$/i.test(path)) {
    const width = /^\d+$/.test(label) ? Math.min(4096, Number(label)) : null;
    return `<img src="${escape(resourceURL(path))}" data-path="${escape(path)}" alt="${escape(/^\d+$/.test(label) ? path.split('/').pop() : label || target)}" loading="lazy"${width ? ` style="max-width:min(100%,${width}px)"` : ''}>`;
  }
  return `<a href="${escape(fileURL(path, result.anchor))}">${escape(label || target)}</a>`;
}
md.inline.ruler.before('link', 'wiki', (state, silent) => {
  const rest = state.src.slice(state.pos), match = /^(!?)\[\[([^\]\n]+)\]\]/.exec(rest);
  if (!match) return false;
  if (!silent) {
    const [target, ...alias] = match[2].split('|');
    const token = state.push('html_inline', '', 0);
    token.content = wikiHTML(target, alias.join('|'), !!match[1]);
  }
  state.pos += match[0].length; return true;
});
md.inline.ruler.before('emphasis', 'obsidian_comment', (state, silent) => {
  if (!state.src.startsWith('%%', state.pos)) return false;
  const end = state.src.indexOf('%%', state.pos + 2);
  if (end < 0) return false;
  state.pos = end + 2; return true;
});
md.inline.ruler.before('emphasis', 'highlight', (state, silent) => {
  if (!state.src.startsWith('==', state.pos)) return false;
  const end = state.src.indexOf('==', state.pos + 2);
  if (end < 0) return false;
  if (!silent) { const t = state.push('html_inline', '', 0); t.content = `<mark>${escape(state.src.slice(state.pos + 2, end))}</mark>`; }
  state.pos = end + 2; return true;
});
const defaultLink = md.renderer.rules.link_open || ((t, i, o, e, s) => s.renderToken(t, i, o));
md.renderer.rules.link_open = (tokens, i, options, env, self) => {
  const token = tokens[i], href = token.attrGet('href') || '';
  if (!/^[a-z][a-z\d+.-]*:/i.test(href)) {
    const result = tree.relative(href, currentPath);
    if (result.path) token.attrSet('href', fileURL(result.path, result.anchor));
    else { token.attrSet('class', 'dead-link'); token.attrSet('title', '未找到'); token.attrSet('href', '#missing'); }
  } else if (!href.startsWith('vault:')) { token.attrSet('class', 'external'); if (href.startsWith('obsidian:')) token.attrSet('title', '另一 vault'); }
  return defaultLink(tokens, i, options, env, self);
};
const defaultImage = md.renderer.rules.image;
md.renderer.rules.image = (tokens, i, options, env, self) => {
  const token = tokens[i], source = token.attrGet('src') || '';
  if (!/^https:\/\//i.test(source)) {
    const result = tree.relative(source, currentPath);
    if (!result.path) return '<span class="dead-link">图片未找到</span>';
    token.attrSet('src', resourceURL(result.path)); token.attrSet('data-path', result.path);
  }
  token.attrSet('loading', 'lazy');
  const width = /\|(\d+)$/.exec(token.content);
  if (width) { token.attrSet('style', `max-width:min(100%,${Math.min(4096, Number(width[1]))}px)`); token.content = token.content.replace(/\|\d+$/, ''); }
  return defaultImage(tokens, i, options, env, self);
};
md.renderer.rules.heading_open = (tokens, i, options, env, self) => {
  tokens[i].attrSet('id', headingID(tokens[i + 1]?.content || ''));
  return self.renderToken(tokens, i, options);
};
function frontmatter(source) {
  const match = /^(?:\uFEFF)?---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/.exec(source);
  if (!match) return { content: source, properties: '', tags: [] };
  const yaml = match[1], tags = [];
  let inTags = false;
  const unquote = s => s.trim().replace(/^['"]|['"]$/g, '');
  for (const line of yaml.split(/\r?\n/)) {
    if (/^tags\s*:/.test(line)) {
      inTags = true;
      const value = line.replace(/^tags\s*:\s*/, '').trim();
      if (value) tags.push(...value.replace(/^\[|\]$/g, '').split(/,\s*/).map(unquote).filter(Boolean));
    } else if (inTags && /^\s*-\s+/.test(line)) tags.push(unquote(line.replace(/^\s*-\s+/, '')));
    else if (/^\S/.test(line)) inTags = false;
  }
  return { content: source.slice(match[0].length), properties: yaml, tags };
}
DOMPurify.addHook('afterSanitizeAttributes', node => {
  if (node.tagName === 'IMG') {
    const src = node.getAttribute('src') || '';
    if (!/^vault:\/\/file\//.test(src) && !/^https:\/\//i.test(src)) node.removeAttribute('src');
    node.removeAttribute('srcset');
  }
  if (node.hasAttribute?.('style') && !/^max-width:min\(100%,\d+px\)$/.test(node.getAttribute('style'))) node.removeAttribute('style');
});
const setTree = entries => { tree = createTree(entries); lastContent = null; };
const render = (source, path, fontScale = 1, colorScheme = 'light') => {
  const scroll = lastPath === path ? window.scrollY : 0;
  currentPath = path;
  const { content, properties, tags } = frontmatter(source);
  document.documentElement.style.setProperty('--font-scale', String(fontScale));
  document.documentElement.dataset.theme = colorScheme;
  if (source !== lastContent || path !== lastPath) {
    const metadata = tags.length ? `<div class="tags">${tags.map(t => `<span>${escape(t)}</span>`).join('')}</div>` : '';
    const props = properties ? `<details class="properties"><summary>属性</summary><pre>${escape(properties)}</pre></details>` : '';
    document.getElementById('content').innerHTML = DOMPurify.sanitize(metadata + props + md.render(content), {
      USE_PROFILES: { html: true }, ADD_ATTR: ['data-path', 'loading'],
      ALLOWED_URI_REGEXP: /^(?:(?:https?|mailto|obsidian|vault):|#)/i,
      FORBID_TAGS: ['script', 'style', 'iframe', 'object', 'embed', 'form', 'video', 'audio'],
      FORBID_ATTR: ['srcset']
    });
    lastContent = source; lastPath = path;
    requestAnimationFrame(() => window.scrollTo(0, scroll));
  }
  emit('height', { px: document.documentElement.scrollHeight });
  return true;
};
const scrollToAnchor = anchor => { const el = document.getElementById(headingID(anchor)); if (el) el.scrollIntoView(); else window.scrollTo(0, 0); };
document.addEventListener('click', event => {
  const img = event.target.closest('img[data-path]');
  if (img) { event.preventDefault(); emit('preview', { path: img.dataset.path }); return; }
  const a = event.target.closest('a');
  if (!a) return;
  event.preventDefault();
  if (a.classList.contains('dead-link')) return;
  const href = a.getAttribute('href');
  if (href?.startsWith('#')) { document.getElementById(href.slice(1))?.scrollIntoView(); return; }
  emit('open', { href });
});
document.addEventListener('error', event => {
  if (event.target.tagName === 'IMG') { event.target.alt = '图片暂不可用，联网后刷新重试'; event.target.classList.add('image-error'); }
}, true);

window.VaultReader = Object.freeze({ version: 1, setTree, render, scrollToAnchor });
