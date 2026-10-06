# AniCh 个人学习修改版

基于 [Sle2p/AniCh](https://github.com/Sle2p/AniCh) 在 2026-10-06 获取的 `main`：
`c5729a28af239aec78c7059ad122ff00f3f7c47a`。

上游公开 README 和 pubspec 仍标注源码版本 1.0.0，与发布页、用户截图中的界面有差异。本次修改使用上述公开源码，不包含发布包中未公开的代码。

## 使用方式

### 逐集匹配弹幕

- 宽屏播放页右侧选择“资源与弹幕”，找到“弹幕源”；窄屏在简介区域使用同一面板。全屏可从播放器的弹幕源按钮打开面板。
- 哔哩哔哩、哔哩哔哩（港澳台）、腾讯视频各行的菜单包含“搜索匹配”和“链接加载”。搜索后先选择视频或合集，再选择具体一集；不会把合集第一集自动绑定到当前集。
- B 站支持 BV、AV、番剧 ep/ss 链接、带 `p=` 的分 P 链接、b23 分享链接和 `cid:数字`；腾讯支持单集播放链接、合集链接和 `vid:视频ID`。
- 手动匹配、来源开关和时间偏移按 AniCh 番剧 ID 与当前集数保存。切集取消旧请求，返回该集时恢复其匹配。菜单可以重新加载、调整偏移或恢复自动匹配。
- “服务端弹幕”有独立开关，关闭会取消请求并清空此来源的缓存。全局弹幕设置另有默认开关，已保存的逐集设置优先。
- 服务端弹幕是原 AniCh 接口来源；其他平台弹幕由客户端读取。平台访问限制会显示失败提示，可重试或使用具体视频链接。

### 播放速度与字幕

- 普通播放和全屏播放的右下角均有倍速菜单，提供 0.25× 到 2.0×。切换线路后应用当前倍速。
- 线路列表显示 `字幕：简体／繁体／未知`。只采用 CHS、CHT、简中、繁中等明确字幕信息；标题的汉字写法、清晰度或“中日双语”不会单独作为判据。无法确定、同时含简繁标记时显示“未知”。
- 宽屏右侧保留“评论”标签，窄屏仍使用原简介与评论标签。

### 以图搜番

- 搜索栏和搜索面板新增“以图搜番”入口。
- 可选择本地图片或输入图片 URL，结果显示番名、集数、画面时间、相似度、预览图，并可打开片段或继续搜索番剧。
- 识别使用 trace.moe，参考 Kazumi 的截图识别流程。只有点击“识别番剧”才发送所选图片或链接。限制 25 MB，并显示额度、频率与网络错误。
- 低相似度结果需要对照确认；外语番名可能需要在 AniCh 搜索中手动改用中文名。

### 取消强制更新

- 启动时不再自动检查上游版本，不会因作者发布主版本或次版本更新而阻断进入应用。
- “关于”页保留手动检查，所有新版提示均可点击“继续使用”、按返回或点击遮罩关闭。更新按钮仅打开上游发布页面。
- 这关闭的是客户端更新弹窗；上游服务将来停用接口时，旧版服务端资源仍可能不可用。

### 次元城与 girigirilove

- 在“视频资源”点击“搜索次元城 / girigirilove”，选择网站，搜索番剧并选择具体线路、具体集数。播放地址作为当前集的可选线路加入列表。
- 次元城固定使用 `https://www.cycani.org/`，girigirilove 固定使用 `https://ani.girigirilove.com/`。没有加入稀饭动漫。
- 网站匹配按集保存；再次进入时重新获取播放地址，以适应签名地址过期。
- girigirilove 支持目前的 `/GV…/`、`/playGV…/` 页面及简中线路，支持网站当前播放器 JSON 中的明文、URL 编码和 Base64 编码地址。若搜索触发图片验证码，会显示图片供用户输入；不自动识别验证码。
- 次元城播放接口需要网站账号时弹出登录窗口。密码不保存，登录令牌和网站会话仅保留在本次进程内。

## 验证与实际限制

### 首页空白修复

- 旧首页接口在排查时未返回可用内容；关闭客户端强制更新不能恢复停用或拒绝访问的服务端接口。
- 首页请求增加连接与接收超时，拒绝空 HTTP 响应和错误数据包。有效空列表显示“首页暂无内容”，失败显示“首页加载失败”，两者都提供重试与网站资源入口。
- 首页与番剧页底部新增“网站资源”。次元城、girigirilove 可直接搜索、选择线路和集数，通过独立播放页播放，无需原服务端提供番剧详情、剧集或视频地址。播放页仍支持右侧弹幕匹配与右下角倍速。
- 网站播放使用独立的本地视频标识保存弹幕匹配和播放进度。历史记录点击后重新搜索原番剧，选择原线路和集数即可续播；不保存可能过期的签名播放地址。
- 此修复在本地和 GitHub Actions 通过 26 项测试，包含首页空数据、错误数据包、重试恢复、网站入口及网站播放不请求原服务端的回归测试。Windows x64 Release 构建成功，源码提交为 `2789c97ea7378a20a969390eb10dabf82a119203`。

在 Flutter 3.47.5 / Dart 3.13.4 下完成：

- 21 项单元及 Widget 测试通过（包含上游主版本更新提示可关闭），包含分集隔离、旧请求取消、手动匹配优先、偏移、字幕判据、平台解析、网站验证码会话与倍速菜单。
- Dart 静态检查没有错误；上游 `ns_danmaku/danmaku_view.dart` 的不可达 default 警告及原有弃用提示仍存在。
- `flutter build bundle --no-pub --target-platform=windows-x64` 成功，确认完整应用 Dart 代码能编译。此结果是 Flutter bundle，不是可安装 Windows 程序。
- 在线样例：B 站“樱花庄”返回 24 集，首段读取 2842 条弹幕；腾讯返回 24 集，首段读取 429 条弹幕。普通 BV 视频信息接口也返回有效信息。样例数量会随平台更新而变化。
- 次元城搜索和分集读取成功；girigirilove 简中线路和 HTTPS 播放地址解析成功。

GitHub Actions 在 2026-10-06 完成 Windows x64 Release 原生构建，云端依赖解析、静态检查（允许已有警告／提示）、21 项测试、EXE 编译及产物校验全部成功。生成 `xs.exe` 和完整运行目录，ZIP 大小 34,997,251 字节。构建源码提交为 `b10dfff98a5a2684e35ffddc8a8b9bc63874a725`。

没有完成的端到端验证：尚未在用户电脑运行 Windows 程序；未生成 Android APK；次元城账号登录与登录后播放、girigirilove 人工验证码提交以及 trace.moe 真实截图识别尚未在运行中的应用内验证。网站接口、访问限制和资源可用性仍由各平台决定。

## 构建与学习

新增直接依赖 `html`，用于 HTML 解析。依赖锁文件在本机 SDK 与缓存条件下重新解析，包含原依赖版本更新；当前锁文件要求 Dart >=3.13、Flutter >=3.44。建议用上述验证版本复现。依赖镜像为 `https://pub.flutter-io.cn`，可以通过自己的环境配置替换。

```sh
flutter pub get
flutter test --no-test-assets
flutter analyze
flutter build windows
# 已安装 Android SDK 的环境：
flutter build apk
```

Windows 构建需要 Visual Studio 的“使用 C++ 的桌面开发”组件。上游平台工程和原有插件仍可能需要适配具体 SDK；本次未改动原生平台代码。

### 使用 GitHub Actions 构建 EXE

`.github/workflows/build-windows.yml` 在公开仓库中提交源码时自动构建，也可从 Actions 的“Build Windows EXE”手动运行。使用标准 `windows-2022` runner 和 Flutter 3.47.5，依次进行依赖解析、静态检查、测试与 Windows Release 构建。该任务在私有仓库中跳过。

成功后下载 `AniCh-Windows-x64` artifact，完整解压后运行 `xs.exe`。必须同时保留 DLL 和 `data` 文件夹；不能只复制 EXE。产物保留 7 天，没有使用大型付费 runner 或额外缓存。

首页修复版的 [成功构建记录](https://github.com/duolaxing/AniCh-study/actions/runs/37465040182) 和 [Windows 产物下载](https://github.com/duolaxing/AniCh-study/actions/runs/37465040182/artifacts/11413859530)。ZIP 大小 35,002,616 字节，产物在 2026-10-13 到期；之后可重新运行该工作流。需登录 GitHub 下载 Actions artifact。

首页修复版 ZIP 的 SHA-256：`34e6e26ac15c3a6185132f0ca434cbe1e5a92f496bd9db4c76857525e13e64ba`。

主要入口：

| 功能 | 源码 |
| --- | --- |
| 逐集来源状态与持久化 | `lib/src/services/episode_danmaku.dart` |
| B 站、腾讯搜索／分集／弹幕 | `lib/src/services/platform_danmaku.dart` |
| 右侧弹幕源面板 | `lib/src/pages/bangumi_vod/views/danmaku_sources.dart` |
| 网站资源适配 | `lib/src/services/website_sources.dart` |
| 网站搜索、登录与验证码 | `lib/src/pages/website_source/view.dart` |
| 字幕类型判据 | `lib/src/utils/subtitle_language.dart` |
| 图片识别接口和页面 | `lib/src/services/image_search.dart`、`lib/src/pages/image_search/view.dart` |
| 播放速度控件 | `lib/src/widgets/player/controls.dart` |
| 回归测试 | `test/source_features_test.dart`、`test/widget_test.dart`、`test/update_test.dart` |

附带补丁可应用到上述上游提交：先检查 `git apply --check AniCh-changes.patch`，再执行 `git apply AniCh-changes.patch`。已有个人修改的仓库应先保存当前工作再核对补丁。
