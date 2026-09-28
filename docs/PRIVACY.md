# Vault Reader 隐私政策 / Privacy Policy

生效日期 / Effective date: 2026-09-28

## 中文

Vault Reader 由独立开发者 Wei Dong 提供，是用于阅读你自己的 GitHub 或 GitLab 知识库的只读应用。应用没有开发者运营的同步服务器、注册账号系统、广告或内置使用行为分析服务。

## 仓库连接与凭据

当你连接知识库时，应用直接通过 HTTPS 向你选择的 GitHub、GitLab.com 或自建 GitLab 服务请求仓库文件和提交记录。服务提供商会收到完成请求所需的 Token、仓库路径、网络地址及请求信息，并按其隐私政策处理。Token 保存在设备 Keychain，不写入应用偏好、日志或网页渲染层；凭据不会发送给应用开发者。请只授予需要阅读的仓库所需的只读权限。

## 本机数据

应用在本机保存仓库配置、已下载文件、目录与提交缓存、搜索索引、阅读位置和显示偏好。示例知识库使用合成内容，并与真实仓库的缓存和阅读位置分开保存。应用不向开发者上传这些内容。部分本机设置和阅读记录可能包含在你启用的系统设备备份中；Token 使用仅限本机的 Keychain 保护，文件缓存标记为不参与备份。

## 网页、外部资源和分享

Markdown 可包含 HTTPS 图片，独立 HTML 文档可以运行其自身脚本并请求外部资源。打开这些内容可能直接联系内容作者指定的第三方服务器；其网络请求与数据处理受对应服务的政策约束。HTML 文档没有访问应用 Token 或原生凭据的接口。点击外部链接会打开系统浏览器；使用系统分享菜单时，仅你选择的接收应用或接收方会收到所分享的文字。请仅打开和分享你信任且有权使用的内容。

## 保留、删除与撤销权限

缓存会按照应用设置管理；已下载的 Markdown 和 SVG 会保留用于离线阅读。你可以在设置中清理附件缓存，或选择“移除本机 Token”停止该仓库的联网同步。移除 Token 不会删除已缓存内容或阅读位置。要撤销服务端访问权限，请到 GitHub 或 GitLab 的 Token 管理页面撤销对应 Token。若要清除本机所有应用数据，请先移除已保存的 Token，再通过 iOS 删除应用（不是“卸载 App”保留数据选项）；单独删除应用未必清除系统 Keychain 中的凭据。备份中的副本需通过你自己的系统备份设置管理。

## 联系与变更

隐私问题和支持请求可通过 [Vault Reader 支持页面](https://github.com/dwroy/vault-reader/issues) 提交。该页面上的问题是公开的，请勿提交 Token、私有仓库内容或其他敏感信息；一般隐私问题不需要提供这些数据。重大数据处理变化会随应用更新反映在本政策中。

## English

Vault Reader is a read-only app by independent developer Wei Dong for your own GitHub or GitLab knowledge bases. The developer operates no synchronization backend or app account system. The app contains no advertising or usage analytics service.

## Repository connections and credentials

When you connect a repository, the app sends HTTPS requests directly to your selected GitHub, GitLab.com or self-managed GitLab service. That provider receives the token, repository paths, network address and request information needed to serve your requests, under its own privacy policy. Tokens stay in the device Keychain, never in app preferences, logs or the web renderer, and are not sent to the app developer. Grant only the read access needed for the repositories you use.

## Data on your device

Repository settings, downloaded files, directory and commit caches, search indexes, reading positions and display preferences are stored locally. Synthetic samples have separate caches and reading positions. The app does not upload this information to the developer. Some settings and reading records may be included in system device backups you enable. Tokens use device-only Keychain protection; renewable file caches are excluded from backup.

## Web content, external resources and sharing

Markdown may load HTTPS images. Independent HTML documents can run their own scripts and request external resources. Opening such content can contact servers selected by the content author, whose data practices are governed by those services. HTML documents have no interface to app tokens or native credentials. External links open in the system browser. When you use the system share sheet, the selected destination receives the text you choose to share. Open and share only content you trust and have permission to use.

## Retention, removal and revoking access

Cache management follows your app settings; downloaded Markdown and SVG files are retained for offline reading. Settings lets you clear attachment caches and remove the active repository's local token. Removing a token stops online synchronization but keeps cached files and reading progress. Revoke the token at GitHub or GitLab to revoke server-side access. To remove local app data, first remove saved tokens, then delete the app in iOS rather than offloading it. Deleting the app alone may leave credentials in the system Keychain. Manage backup copies through your system backup settings.

## Contact and changes

Use [Vault Reader support](https://github.com/dwroy/vault-reader/issues) for questions. Issues are public: do not include tokens, private repository contents or sensitive information. General privacy questions do not require that information. Material changes in data handling will be reflected in this policy with an app update.
