# Reading list format

Vault Reader lists books from one or more reading-list Markdown files. The same format works in any GitHub or GitLab vault, whatever its folder layout, and stays readable and clickable in Obsidian.

## 1. Declaring the list

Add a `书单` (or `booklist`) property to the frontmatter of the root `README.md`:

```yaml
---
书单: study/read/书单.md
---
```

The value may be a repository-relative path, a path without `.md`, a quoted wikilink (`"[[书单]]"`, as Obsidian writes link properties), a Markdown link, or a YAML list of any of these for several lists:

```yaml
---
书单:
  - study/read/书单.md
  - "[[论文清单]]"
---
```

Only indexed Markdown targets are used. Missing files, traversal outside the vault and non-Markdown targets are ignored. A `书单:` line in the README body is not a declaration.

**Fallback.** When the README declares nothing (or there is no README), the app reads every file named `书单.md` or `booklist.md` (any case, any folder), then top-level Markdown in folders named `read`, `reading`, `books`, `papers` or `articles`. If none of those declare books, the app groups reading-folder files by subfolder as before.

## 2. List structure

```markdown
# 书单

## 在读                                   ← group (optional)

### 置身事内：中国政府与经济发展              ← book
- 作者：兰小欢
- 状态：复习中
- 评分：⭐️⭐️⭐️⭐️
- 原书：[电子版 PDF](../../files/置身事内.pdf)（249 页）
- 全文：[[置身事内-原文|OCR 全文]]
- 精简版：[[置身事内-精简版|逐章详版]]
- 阅读器：[阅读器](置身事内/置身事内-阅读器.html)
- 笔记：
  - [[置身事内-复习笔记|复习笔记]]
  - [[置身事内-第三章追问]]
- 评论：地方政府如何做经济的一本好入门。
- 备注：2026-07 逐章重读
```

- `##` headings are groups, shown in file order. `###` headings are books. A heading counts as a book only if it has at least one recognized key, so other sections (introductions, “相关”) are ignored. A `##` heading with recognized keys directly under it is also a book.
- Each property is a top-level list item `- key：value` (full-width `：` or `:`; `**key**` is allowed). Indented list items continue the previous key, which suits books with many notes.
- Headings and items inside code fences are ignored. Frontmatter in the list file is ignored.

## 3. Keys

| Key (aliases) | Meaning | App section |
| --- | --- | --- |
| 作者 (`author`) | author text | header |
| 状态, 进度 (`status`) | reading status text | header, list row |
| 评分 (`rating`) | rating text, e.g. ⭐️⭐️⭐️⭐️ | header, list row |
| 备注 (`note`) | free text; may repeat | header |
| 精简版, 简化版, 精简, 详版 (`condensed`) | condensed edition | 精简版 |
| 全文, 原文, 整理版 (`fulltext`) | organized full text | 全文 |
| 阅读器 (`reader`) | HTML reader or web link | 阅读器 |
| 原书, 原版, 导入, 附件 (`original`) | imported PDF/EPUB | 原书 |
| 笔记, 读书笔记, 阅读笔记, 复习笔记 (`notes`) | reading notes | 读书笔记 |
| 评论, 书评, 短评, 感想 (`review`) | review files, or plain text as a short comment | 评论 |
| 入口, 相关, 其他 (`other`) | entry pages and related notes | 其他 |

Unknown keys are ignored. File sections are shown in the order of this table.

## 4. Links

- `[[name]]`, `[[name|label]]`, `[[folder/name]]` and the table-style escaped `[[name\|label]]` resolve like the shared renderer (`packages/reader-web/src/tree.js`): same folder as the list first, then the shallowest path, then lexical order.
- `[label](relative/path)` and `[label](<path with spaces>)` are relative to the list file; a leading `/` is relative to the vault root. Percent-encoding is decoded; `.md` may be omitted.
- `https://` and `http://` targets, as links, autolinks or bare URLs, open in Safari and are never fetched. Other schemes (`obsidian://`, `file://`) are dropped.
- Several links may share one item, separated by `、` or commas. Text beside a single link, such as `（380 页，扫描本）`, is shown under that file.
- Unresolved targets remain visible as “未找到” rows so a broken list is noticed.

## 5. App behaviour

- Reading shows groups and books in list order. A book row shows author, status, rating and the most recent position among its files. Opening it shows the file sections above with per-file progress.
- Reading-folder files not mentioned by any list appear under “未列入书单”.
- Recent reading shows the three most recently read Markdown documents. PDF and HTML progress is saved and shown on the book page, but those files are not listed as recent.
- Lists are parsed only on the device. The app never writes to the vault.
