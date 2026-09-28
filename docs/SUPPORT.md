# Vault Reader 使用帮助 / Support

## 先体验，再连接

欢迎页点击“体验示例知识库”，即可离线体验目录、双链、搜索、阅读书架、PDF、HTML 和阅读进度。示例完全虚构；不会连接你的仓库，也不会覆盖已保存的连接。目录右上角菜单 → 设置 → “退出示例知识库”可回到原来的仓库或欢迎页。

## 连接 GitHub

在 GitHub 创建 fine-grained personal access token。Resource owner 选择仓库所属账户，Repository access 只选择需要阅读的仓库，Repository permissions 中 Contents 选择 Read-only，保留所需的 Metadata 只读权限。组织仓库可能需要组织管理员批准。应用内填写 Owner、Repository 和分支，粘贴 Token 后点击“保存并校验”。Token 只填在应用安全输入框中，不要发送给开发者。

## 连接 GitLab

选择 GitLab，填写 HTTPS 服务地址（例如 https://gitlab.com）、命名空间、仓库名称和分支。命名空间可为 group/subgroup。使用 read_api 范围的 Token；如你的实例提供项目 Access Token，优先限制到目标项目。自建实例需使用设备信任的 HTTPS 证书。公开项目目前也使用 Token 连接流程。

## 阅读与离线

目录用于浏览文件；阅读页按项目组织书籍与文章；最近页显示仓库提交；搜索支持文件名和已缓存 Markdown 正文。阅读位置保存在本机，未提供跨设备进度同步。缓存完成的内容可离线阅读，未下载的附件仍需要联网。独立 HTML 可以请求第三方网络资源，因此并非所有 HTML 都能完整离线使用。

## 常见问题

“Token 无效或已过期”：检查到期时间、Token 平台及仓库权限，重新保存新的只读 Token。403 也可能由组织限制或 API 配额造成；按错误提示处理。找不到仓库：检查 Owner/命名空间、Repository 和分支的拼写。无法打开附件：确认已联网，文件不超过 100 MiB，且不是仅有指针的 Git LFS 文件。不要依赖应用完整复现 Obsidian 插件、Dataview 或脚本功能。

## 数据与隐私

设置可清理附件缓存、移除本机 Token。移除凭据保留缓存和阅读进度。要彻底撤销访问，请在 GitHub/GitLab 中撤销 Token。完整说明见应用内“隐私政策”或 [在线隐私政策](https://github.com/dwroy/vault-reader/blob/main/docs/PRIVACY.md)。

## 反馈与支持

通过 [GitHub Issues](https://github.com/dwroy/vault-reader/issues) 联系开发者。请提供应用版本、设备型号、iOS 版本、复现步骤和已脱敏的错误信息。问题公开可见，请勿提交 Token、私有仓库文件、真实知识库截图或包含私人路径的日志。尽量用合成的小样例复现问题。

## English quick start

Tap “体验示例知识库” (Try sample library) on the welcome screen to explore without an account or network connection. The samples are synthetic and separate from your saved connections. Use Directory → menu → Settings → “退出示例知识库” (Exit samples) to return. The first release's app interface is primarily Simplified Chinese; this guide and store description are also available in English.

## Connect your repository

GitHub: create a fine-grained token limited to selected repositories with Contents: Read-only and the required Metadata access. Enter owner, repository and branch in the app. Organization repositories may require approval. GitLab: enter the HTTPS server, namespace (including subgroups), repository and branch, using read_api access. Prefer a project-scoped token where available. Public repositories currently use the same token setup. Paste tokens only into the app, never into a support message.

## Read and resume

Browse Directory, Reading, Recent and Search. Cached documents are available offline; uncached attachments and third-party HTML resources may require a network connection. Reading progress is local to this device. Downloads are limited to 100 MiB per file. Git LFS pointer files and Obsidian plugins are not supported as full content or plugin execution.

## Get help

For an expired token, create and save a replacement with the correct permissions. For permission or quota errors, follow the app message and check the repository service. Report reproducible problems through [GitHub Issues](https://github.com/dwroy/vault-reader/issues), including app/device/OS versions and sanitized steps. Issues are public; do not include credentials, private files, screenshots of real vaults or private paths. Read the [privacy policy](https://github.com/dwroy/vault-reader/blob/main/docs/PRIVACY.md) for storage and deletion details.
