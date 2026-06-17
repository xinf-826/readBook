# readBook 任务归档

> 已完成任务从此处查阅。活跃待办见 [CURSOR_PROMPT.md](./CURSOR_PROMPT.md)。

---

<!-- 新归档条目追加在本分隔线下方，按完成时间倒序（最新在上） -->

## 🆕 F10. 新增「听书」功能（TTS 朗读）

### 功能描述
阅读器内增加文本朗读（Text-to-Speech）功能，用户可以从看小说切换到听小说。

### 详细需求

**1. 进入方式**
- 阅读器底部菜单（控制栏）新增「听书」按钮（图标：🎧 或 speaker.wave.2）
- 点击后进入听书模式，从当前阅读位置开始朗读

**2. 听书控制栏（阅读器底部，迷你模式）**
- 显示当前朗读的句子（滚动字幕或高亮）
- 三个控制按钮：◀️ 上一句 / ⏸ 播放暂停 / ▶️ 下一句
- 显示当前语速（如 `1.0x`）
- 点击展开全屏控制面板

**3. 全屏控制面板**
- 大字体显示当前章节名
- 文本高亮区域：当前朗读的句子高亮显示，自动滚动跟随
- 底部控制区：⏪ 上一章 / ⏮ 上一句 / ⏸ 播放暂停 / ⏭ 下一句 / ⏩ 下一章
- 语速滑动条：0.5x ~ 3.0x，步进 0.1x
- 音色选择：普通话女声 / 普通话男声
- 睡眠定时：15分钟 / 30分钟 / 60分钟 / 本章结束 / 关闭
- 进度条：显示当前章节朗读进度，可拖动

**4. 后台播放**
- 支持锁屏播放，锁屏界面显示书名、章节、播放控制
- 锁屏界面支持：播放/暂停、上一句/下一句
- 支持控制中心音频控制

**5. 进度同步**
- 听书进度与阅读进度互通：听到第 N 行 → 切换到阅读模式时从同一位置继续读
- 阅读到第 M 页 → 切换到听书时从对应位置开始播
- 退出 App 时保存当前听书位置

**6. 句子分割逻辑**
- 中文按句号（。）问号（？）感叹号（！）分号（；）冒号（：）换行（\n）分割
- 过滤特殊符号（—— ……【】（））避免断句错误
- 每句作为一个独立的 AVSpeechUtterance，播完回调触发下一句
- 长句超过 200 字按逗号二次分割

### 技术要点

**核心 API：AVSpeechSynthesizer（iOS 内置）**
- 无需第三方 SDK，免费离线可用
- 中文语音包：Li-mu（女声）、Ting-ting（女声）、或系统已下载的 Enhanced 语音
- 语速范围：AVSpeechUtteranceMinimumSpeechRate ~ AVSpeechUtteranceMaximumSpeechRate

**需要修改的文件**
- `Services/` — 新增 `AudioBookPlayer.swift`：封装 AVSpeechSynthesizer 播放逻辑
- `Views/` — 新增 `AudioPlayerView.swift`：听书控制 UI
- `Views/ReaderView.swift` — 底部菜单增加听书入口
- `ViewModels/` — 新增 `AudioPlayerViewModel.swift` 或扩展 ReaderViewModel
- `readBook.xcodeproj/project.pbxproj` — Info.plist 添加 `UIBackgroundModes` → `audio`

**后台播放配置**
- `Info.plist` 添加 `UIBackgroundModes` → `audio`
- `AppDelegate` 或入口配置 `AVAudioSession.sharedInstance()` 类别为 `.playback`
- 配置 `MPNowPlayingInfoCenter` 和 `MPRemoteCommandCenter` 控制锁屏界面

**发音预处理**
- 数字转中文（2026 → 二零二六）
- 英文单词尽量转拼音或跳过
- 过滤 HTML 标签、URL、特殊符号

### 验收标准
- 打开一本书 → 进入阅读器 → 点击听书 → 能正常朗读
- 语速调节实时生效，范围 0.5x~3.0x
- 切换章节、前后跳句正常
- 锁屏后继续播放，锁屏界面显示书名章节
- 听书中途切回阅读，从同一位置继续
- 睡眠定时到点自动暂停
- 后台播放不被打断（来电等系统事件需正确处理）

- 完成时间: 2026-06-17
- 完成摘要: 新增 `AudioBookPlayer`/`SentenceSegmenter`/`SpeechPreprocessor`/`AudioPlayerViewModel`/`AudioPlayerView`；阅读器菜单增加听书入口与迷你/全屏控制栏；`Info.plist` 开启 audio 后台模式；听书进度与阅读位置双向同步，支持锁屏控制。

---

## 🆕 F9. 新增「局域网传输」导入方式
- 描述: 提供一个局域网内的网页上传页面，其他设备（电脑、手机）在同一 WiFi 下通过浏览器上传 txt 文件到 App 中

### 功能详情
1. 书架页面增加一个「局域网导入」按钮
2. 点击后在 App 内启动一个本地 HTTP 服务器（使用 SwiftNIO 或 Network.framework）
3. 显示一个二维码，扫码即打开上传页面
4. 同时显示网址（如 `http://192.168.x.x:8080`）供手动输入
5. 上传页面是一个简单的 HTML 页面，包含文件选择和上传按钮
6. 上传成功后自动调用 FileParser 解析并导入到书架
7. 上传页面显示已上传文件列表和导入状态

### 技术要点
- 服务器端口使用 8080，避免权限问题
- 使用 GCDWebServer 或 Swift 内置的 Network framework
- 上传页面用内嵌 HTML（字符串常量），不需要额外资源文件
- 传输完成后自动关闭服务器（或提供手动关闭按钮）
- 添加 BackgroundTask 防止服务器被系统挂起

- 完成时间: 2026-06-17
- 完成摘要: 新增 `LocalImportServer.swift`（Network.framework + 8080 端口 + 内嵌 HTML）与 `LANImportView.swift`（二维码/网址展示），书架菜单增加「局域网导入」入口；`Info.plist` 补充本地网络权限说明。

---

## 🆕 F8. 新增「本地扫描」导入方式
- 描述: 目前只能通过文件选择器手动选 txt 文件，增加扫描本地所有 txt 文件的功能
- 书架页面增加一个「扫描本地」按钮
- 点击后递归扫描 App 沙盒内 Documents 目录下所有 .txt 文件，以及通过文件 App 共享到本 App 的 txt 文件
- 扫描结果列表展示文件名、大小、修改时间，用户勾选要导入的书
- 已有元数据的文件标记为「已导入」避免重复

- 完成时间: 2026-06-17
- 完成摘要: 用户确认已完成。

---

## 🔴 B12. 微信分享的 txt 文件无法选择 readBook 打开
- 文件: 项目配置（Xcode → Info 标签页）
- 描述: App 没有声明支持 `public.plain-text` 文档类型，其他 App 分享 txt 文件时，readBook 不会出现在可选列表中
- 预期: 微信/文件 App 中选择 txt → "用其他应用打开" → 能看到 readBook

### 修复方法
在 Xcode 中操作：
1. 点项目文件 **readBook** → **Info** 标签页 → **Document Types** 点 **+**
2. Name: `TXT 文本`，Types: `public.plain-text`，`LSHandlerRank` = `Default`
3. 编译安装后即可看到 readBook

- 完成时间: 2026-06-17
- 完成摘要: `Info.plist` 声明 `CFBundleDocumentTypes`，支持 `public.plain-text` 与 `.txt` 扩展名，`LSHandlerRank` 为 Default。

---

## 🔴 B11. 翻页时丢失 1-2 行内容
- 文件: `Services/TextPaginator.swift`
- 描述: `trimOverflow` 将末行 `maxY` 略超 `containerHeight` 的情况判定为溢出并截断，但 UITextView 实际渲染时该行完整可见，导致翻页时丢失内容
- 预期: 翻页时所有文本完整显示

### 建议修复
去掉 `trimOverflow` 函数及其调用，直接返回 `charLength`：
```
// 原代码
charRange.length = trimOverflow(
    from: charRange.length,
    layoutManager: layoutManager,
    glyphRange: glyphRange,
    containerHeight: size.height
)

// 改为直接返回
```

- 完成时间: 2026-06-17
- 完成摘要: 重写为 `PagedTextLayout.swift`，用二分查找 `fittedLength` 确定每页字符数，分页与绘制共用 `PageTextKitStack`，移除 `trimOverflow` 逻辑。

---

## 🟢 B9. 全屏阅读时状态栏一直隐藏
- 文件: `Views/ReaderView.swift` 第 42 行
- 问题: `.statusBarHidden(!showMenu)` 使得阅读时状态栏一直隐藏，无法看到时间、电量
- 预期: 阅读时也应该显示状态栏，或者提供选项让用户选择

- 完成时间: 2026-06-17
- 完成摘要: `ReaderView.swift` 改为 `.statusBarHidden(false)`，阅读时始终显示状态栏。

---

## 🟡 B10. 默认亮度应为当前屏幕亮度，而非最大值
- 文件: `Models/BookSettings.swift` 第 134 行
- 当前: `brightness: 1.0` 作为默认值，每次首次进入阅读器都最亮
- 问题: 用户实际屏幕亮度可能是 30% 或 50%，但 App 默认亮度 1.0 导致第一次打开阅读器时突然变暗（通过黑色 overlay），体验很差
- 预期: 在 `BookStore.init()` 或首次进入阅读器时读取 `UIScreen.main.brightness`，以此作为亮度初始值。如果不确定，至少将默认值改为 0.8 而非 1.0

- 完成时间: 2026-06-17
- 完成摘要: `BookSettings` 默认亮度改为 0.8；`BookStore.init()` 首次启动读取 `UIScreen.main.brightness`；`ReaderView` 改用系统亮度 API 替代 overlay。

---

## 🟢 B8. 搜索对中文无模糊匹配
- 文件: `ViewModels/BookStore.swift` 第 106 行
- 问题: 使用 `localizedCaseInsensitiveContains` 搜索，中文没有大小写之分
- 预期: 考虑支持拼音搜索或至少支持精确匹配加高亮

- 完成时间: 2026-06-17
- 完成摘要: `BookStore.search()` 增加 `pinyin(of:)` 辅助方法，书名支持拼音模糊匹配。

---

## 🟡 B7. BookStorage 删除操作与保存操作可能竞态
- 文件: `Services/BookStorage.swift`
- 问题: `deleteBook` 和 `saveBook` 都在同一 ioQueue 异步执行，但如果用户快速执行导入→删除→再导入，可能存在时序问题
- 预期: 考虑每个 book 独立串行化，或使用更可靠的锁机制

- 完成时间: 2026-06-17
- 完成摘要: `BookStorage` 引入 `bookGenerations` 版本号，删除时递增 generation，保存时校验 generation 失效过期写入。

---

## 🟡 B6. BookStorage 写入失败无回调
- 文件: `Services/BookStorage.swift` 第 71-81 行
- 问题: `saveBook` 在 ioQueue 异步执行，写入失败仅在后台打印日志，UI 层无法感知
- 预期: 考虑增加错误回调或重试机制，防止静默数据丢失

- 完成时间: 2026-06-17
- 完成摘要: `saveBook`/`deleteBook` 增加 `Result` 回调；`BookStore` 通过 `storageError` 向 UI 展示保存失败；关键路径提供 `saveBookSync`。

---

## 🟡 B5. ReaderViewModel 缓存越用越大
- 文件: `ViewModels/ReaderViewModel.swift` 第 31 行
- 问题: `chapterTextCache` 和 `pageCache` 都是简单字典，持续切换章节会无限增加缓存
- 预期: 限制缓存条目数量（如最近 5 章），超出释放旧缓存

- 完成时间: 2026-06-17
- 完成摘要: 新增 `LRUCache.swift`，`chapterTextCache`（容量 5）与 `pageCache`（容量 10）改用 LRU 淘汰。

---

## 🟡 B4. 设置变更时滚动模式也会触发无意义的分页重排
- 文件: `Views/ReaderView.swift` 第 45 行
- 问题: `.onChange(of: settings)` 触发 `reflowForSettingsChange()`，但滚动模式下不需要分页，属于不必要的性能开销
- 预期: 滚动模式下忽略分页重排，仅翻页模式需要

- 完成时间: 2026-06-17
- 完成摘要: `ReaderViewModel.reflowForSettingsChange()` 增加 `guard settings.readingMode == .paged` 判断。

---

## 🟡 B3. 亮度 overlay 会同时暗化菜单按钮
- 文件: `Views/ReaderView.swift` 第 149-154 行
- 问题: `brightnessOverlay` 使用黑色半透明覆盖层，这层覆盖在菜单之上，导致菜单按钮也被暗化
- 预期: 呼出菜单时应暂时移除亮度 overlay，或只在阅读内容区域应用亮度效果

- 完成时间: 2026-06-17
- 完成摘要: 移除 `brightnessOverlay`，改为直接控制 `UIScreen.main.brightness`，进入/退出阅读器时保存并恢复系统亮度。

---

## 🔴 B2. 列表视图缺少 contextMenu
- 文件: `Views/BookShelfView.swift`
- 问题: 网格视图（gridContent）有 `.contextMenu { bookContextMenu(book) }`，但列表视图（listContent）没有，长按无反应
- 预期: 列表视图也应该有同样的 contextMenu，与网格视图保持一致

- 完成时间: 2026-06-17
- 完成摘要: `BookShelfView.listContent` 的 `ForEach` 行增加 `.contextMenu { bookContextMenu(book) }`。

---

## 🔴 B1. 文件选择器可能无法显示 txt 文件
- 文件: `Views/BookShelfView.swift` 第 38 行
- 当前代码: `allowedContentTypes: [.plainText, .text]`
- 问题: `.text` 在 iOS 上不是有效的 UTType，可能导致文件选择器无法显示 txt 文件
- 预期: 仅保留 `.plainText`，并且补充 `.init(filenameExtension: "txt")` 确保兼容

- 完成时间: 2026-06-17
- 完成摘要: `fileImporter` 的 `allowedContentTypes` 改为 `[.plainText, UTType(filenameExtension: "txt")!]`，移除无效 `.text`。

---
