/** Reader v2. Host-neutral book navigation; no credentials or native paths. */
export interface ReadingSection { id: string; title: string; level: number }
export interface ReadingPosition { heading: string | null; withinHeading: number; fraction: number }
export interface TreeEntry { path: string; sha: string; size?: number; type: 'blob' | 'tree' }
export interface ReaderAPI {
  readonly version: 2;
  setTree(entries: TreeEntry[]): void;
  render(markdown: string, path: string, fontScale: number, colorScheme: 'light' | 'dark' | 'sepia'): boolean;
  scrollToAnchor(anchor: string): void;
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
