// Host-neutral search presentation. Only article text is inspected; no URLs, metadata or credentials.
const ligatures = {'ﬀ':'ff','ﬁ':'fi','ﬂ':'fl','ﬃ':'ffi','ﬄ':'ffl','ﬅ':'st','ﬆ':'st'};
const fold = text => text.normalize('NFD').replace(/\p{Diacritic}/gu, mark => /\p{Script=Inherited}/u.test(mark) ? '' : mark).toLowerCase().replace(/ß/g, 'ss').replace(/ς/g, 'σ').replace(/[ﬀ-ﬆ]/g, value => ligatures[value]);
const excluded = '.properties,.tags,script,style,[hidden],[aria-hidden="true"]';
const blocks = 'p,h1,h2,h3,h4,h5,h6,pre,li,td,th,summary,div,blockquote,details';
export function highlightSearch(terms) {
  const content = document.getElementById('content');
  for (const mark of content.querySelectorAll('mark[data-search-hit]')) mark.replaceWith(...mark.childNodes);
  content.normalize();
  const needles = [...new Set((Array.isArray(terms) ? terms : []).filter(x => typeof x === 'string' && x.trim()).map(fold))].filter(Boolean);
  if (!needles.length) return 0;
  const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT);
  const nodes = []; let text = '', previousBlock = null;
  while (walker.nextNode()) {
    const node = walker.currentNode;
    if (node.parentElement.closest(excluded)) continue;
    const block = node.parentElement.closest(blocks) || content;
    if (block !== previousBlock && text) text += '\n';
    nodes.push({node, start: text.length, end: text.length + node.data.length});
    text += node.data; previousBlock = block;
  }
  // Map folded UTF-16 offsets back to original graphemes (including accents and emoji).
  let normalized = ''; const starts = [], ends = [];
  for (const {segment, index} of new Intl.Segmenter('en', {granularity: 'grapheme'}).segment(text)) {
    const value = fold(segment); normalized += value;
    for (let i = 0; i < value.length; i++) { starts.push(index); ends.push(index + segment.length); }
  }
  const matches = [];
  for (const needle of needles) {
    let from = 0;
    // Bound markup growth for common words in book-length documents; first matches remain deterministic.
    for (let count = 0; count < 1000; count++) {
      const index = normalized.indexOf(needle, from);
      if (index < 0) break;
      matches.push([starts[index], ends[index + needle.length - 1]]); from = index + needle.length;
    }
  }
  const ranges = [];
  for (const range of matches.sort((a, b) => a[0] - b[0] || a[1] - b[1])) {
    const previous = ranges.at(-1);
    if (previous && range[0] <= previous[1]) previous[1] = Math.max(previous[1], range[1]);
    else if (ranges.length < 1000) ranges.push(range);
    else break;
  }
  let cursor = 0;
  for (const {node, start, end} of nodes) {
    while (cursor < ranges.length && ranges[cursor][1] <= start) cursor++;
    if (cursor === ranges.length) break;
    if (ranges[cursor][0] >= end) continue;
    const fragment = document.createDocumentFragment(); let offset = 0;
    for (let i = cursor; i < ranges.length && ranges[i][0] < end; i++) {
      const lower = Math.max(start, ranges[i][0]) - start, upper = Math.min(end, ranges[i][1]) - start;
      if (lower >= upper) continue;
      fragment.append(document.createTextNode(node.data.slice(offset, lower)));
      const mark = document.createElement('mark'); mark.className = 'search-hit'; mark.dataset.searchHit = '';
      mark.textContent = node.data.slice(lower, upper); fragment.append(mark); offset = upper;
    }
    fragment.append(document.createTextNode(node.data.slice(offset))); node.replaceWith(fragment);
  }
  return ranges.length;
}
export function scrollToSearchMatch() {
  const first = document.querySelector('#content mark[data-search-hit]');
  if (!first) return false;
  for (let element = first.parentElement; element; element = element.parentElement) {
    if (element.tagName === 'DETAILS') element.open = true;
  }
  window.scrollTo(0, Math.max(0, first.getBoundingClientRect().top + window.scrollY - window.innerHeight * 0.25));
  return true;
}
