/** Shared iOS / Android contract. Credentials and filesystem paths never cross it. */
export interface TreeEntry { path: string; sha: string; size?: number; type: 'blob' | 'tree' }
export interface ReaderAPI {
  readonly version: 1;
  setTree(entries: TreeEntry[]): void;
  render(markdown: string, path: string, fontScale: number, colorScheme: 'light' | 'dark'): boolean;
  scrollToAnchor(anchor: string): void;
}
export interface ReaderHost {
  /** Native controlled base; iOS vault://file/, Android app asset HTTPS handler. */
  readonly resourceBaseURL: string;
  postMessage(name: 'open', payload: { href: string }): void;
  postMessage(name: 'preview', payload: { path: string }): void;
  postMessage(name: 'height', payload: { px: number }): void;
}
declare global { interface Window { VaultReader: ReaderAPI; VaultHost: ReaderHost } }
