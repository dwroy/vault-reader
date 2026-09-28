/** Reader v2. Host-neutral book navigation; no credentials or native paths. */
export interface ReadingSection { id: string; title: string; level: number }
export interface ReadingPosition { heading: string | null; withinHeading: number; fraction: number }
export interface TreeEntry { path: string; sha: string; size?: number; type: 'blob' | 'tree' }
/** App chrome only; document contents retain their original language and direction. */
export interface ReaderLocalization {
  language: string;
  notFound: string;
  anotherVault: string;
  imageNotFound: string;
  properties: string;
  imageUnavailable: string;
}
export interface ReaderAPI {
  readonly version: 2;
  setLocalization(labels: ReaderLocalization): void;
  setTree(entries: TreeEntry[]): void;
  render(markdown: string, path: string, fontScale: number, colorScheme: 'light' | 'dark' | 'sepia'): boolean;
  scrollToAnchor(anchor: string): void;
  /** Additive v2 API: highlight literal body terms; empty terms clear highlights.
   * Matches span inline elements, ignore case/diacritics and exclude metadata.
   * At most the first 1,000 occurrences are marked to bound DOM growth in books. */
  highlightSearch(terms: string[]): number;
  /** Reveal the first highlighted occurrence, opening enclosing details. False if none. */
  scrollToSearchMatch(): boolean;
  setReadingMode(enabled: boolean): void;
  outline(): ReadingSection[];
  capturePosition(): ReadingPosition;
  restorePosition(position: ReadingPosition): void;
  scrollToSection(id: string): void;
}
export interface ReaderHost {
  readonly resourceBaseURL: string;
  postMessage(name: 'open', payload: { href: string }): void;
  postMessage(name: 'preview', payload: { path: string }): void;
  postMessage(name: 'height', payload: { px: number }): void;
}
declare global { interface Window { VaultReader: ReaderAPI; VaultHost: ReaderHost } }
