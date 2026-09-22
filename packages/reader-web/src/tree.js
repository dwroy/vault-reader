export const decode = value => { try { return decodeURIComponent(value); } catch { return value; } };
export const headingID = value => value.trim().replace(/\s+/g, ' ').toLowerCase();
export function normalize(path) {
  const parts = [];
  for (const part of path.split('/')) {
    if (!part || part === '.') continue;
    if (part === '..') { if (!parts.length) return null; parts.pop(); }
    else parts.push(part);
  }
  return parts.join('/');
}
export const directory = path => path.includes('/') ? path.slice(0, path.lastIndexOf('/')) : '';
export const encodePath = path => path.split('/').map(encodeURIComponent).join('/');
const lexical = (a, b) => a < b ? -1 : a > b ? 1 : 0;
export function createTree(entries) {
  const paths = entries.filter(e => !e.type || e.type === 'blob').map(e => e.path);
  const files = new Map(entries.map(e => [e.path, e]));
  const mdByName = new Map(), anyByName = new Map();
  function add(map, name, path) { map.set(name, [...(map.get(name) || []), path]); }
  for (const path of paths) {
    const name = path.split('/').pop().toLowerCase();
    add(anyByName, name, path);
    if (/\.md$/i.test(name)) add(mdByName, name.slice(0, -3), path);
  }
  function resolve(target, fromPath) {
    const decoded = decode(target).trim();
    const hash = decoded.indexOf('#');
    const anchor = hash < 0 ? '' : decoded.slice(hash + 1);
    let name = hash < 0 ? decoded : decoded.slice(0, hash);
    if (!name) return { path: fromPath, anchor, candidates: [fromPath] };
    const hasExt = /\.[^/.]+$/.test(name) && !/\.md$/i.test(name);
    if (!hasExt) name = name.replace(/\.md$/i, '');
    let candidates;
    if (name.includes('/')) {
      const t = name.replace(/^\//, '').toLowerCase();
      candidates = paths.filter(path => {
        if (!hasExt && !/\.md$/i.test(path)) return false;
        const p = (hasExt ? path : path.replace(/\.md$/i, '')).toLowerCase();
        return p === t || p.endsWith('/' + t);
      });
    } else candidates = (hasExt ? anyByName : mdByName).get(name.toLowerCase()) || [];
    candidates = [...candidates].sort((a, b) => {
      const same = Number(directory(b) === directory(fromPath)) - Number(directory(a) === directory(fromPath));
      return same || a.split('/').length - b.split('/').length || lexical(a, b);
    });
    return { path: candidates[0] || null, anchor, candidates };
  }
  function relative(target, fromPath) {
    const hash = target.indexOf('#');
    const anchor = hash < 0 ? '' : decode(target.slice(hash + 1));
    const raw = hash < 0 ? target : target.slice(0, hash);
    if (!raw) return { path: fromPath, anchor };
    const decoded = decode(raw);
    const path = normalize(decoded.startsWith('/') ? decoded.slice(1) : [directory(fromPath), decoded].filter(Boolean).join('/'));
    return { path: path && (files.has(path) ? path : files.has(path + '.md') ? path + '.md' : null), anchor };
  }
  return { files, paths, mdByName, anyByName, resolve, relative };
}
