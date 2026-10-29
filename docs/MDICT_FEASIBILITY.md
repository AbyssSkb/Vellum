# 本地 MDict 查词方案

调研与实现日期：2026-10-25。本文记录本地查词实现、只读格式探针结果与选型依据；尚未完成的页面、试听和性能验收单独列出。

## 实现与首版范围

Vellum 支持选中 PDF 单词后按 `K`（`Shift-K`）查词，也可将双击用途设为词典。`WKWebView` 显示原词典 HTML，并从同目录 MDD 中按需读取图片、字体和发音。首版支持单部未加密的 MDict 2.x 词典，文字为 UTF-8 或 UTF-16，数据块支持无压缩或 zlib，保留配套 CSS 和 JavaScript。词库由用户提供，不随应用分发。

实现采用原生 Swift 查词层、系统 libz、WebKit 词典浮层和原生音频播放，不需要额外安装 Python 或 Node。初次使用时未选择词典，用户需在**设置 → 通用**中手动选择 `.mdx`；应用不扫描默认词库文件夹。自动发音默认开启，口音默认为美式，可切换为英式或关闭；所选口音录音缺失时跳过自动播放，词条原有的英美发音链接仍可手动播放。自动发音识别当前 OALDPEX 的词头发音标记，其他排版需适配或手动播放。页面资源保持离线，远程请求被阻止。

文本双击用途为词典、AI 或关闭，新安装默认关闭；升级时将旧版明确保存的双击翻译开关迁移为 AI 或关闭。大写 `K` 查词，小写 `k` 保留 Vim 滚动和选区移动。首版不提供多词典管理、全文检索、词形推导或在线发音；其他版本、加密和 LZO 压缩属于后续兼容范围。

## 本地词库证据

以下为用户提供的 OALDPEX 样本只读检查结果；没有修改或整包展开词库，文件不加入仓库：

| 文件 | 字节数 | 作用 |
| --- | ---: | --- |
| `oaldpex.mdx` | 54,173,361 | 词条 |
| `oaldpex.mdd` | 7,035,625 | 第一资源包 |
| `oaldpex.1.mdd` | 970,259,153 | 分卷资源包 |
| `oaldpex.2.mdd` | 1,115,011,718 | 分卷资源包 |
| `oaldpex.css` | 211,134 | 外置样式 |
| `oaldpex.js` | 191,191 | 外置交互脚本 |
| `oaldpex.png` | 59,909 | 配图 |

四个 MDX/MDD 文件头均声明 v2.0、`Encrypted=No`。MDX 声明 UTF-8、HTML、`StripKey=Yes`、`KeyCaseSensitive=No`；标题为 OALDPEX En-Cn 精装版 V2026.10.05。外置 JavaScript 使用 `localStorage` 和 `sound://`，包含在线发音回退逻辑；CSS 引用 Bookerly、Optima、SourceHan 和 LXGW 字体。

一次性 Python 探针放在仓库外的临时环境，读取全部键表和每个记录块的类型字段，没有展开全部资源。结果如下：

| 文件 | 索引条目数 | 记录块数 | 资源统计 |
| --- | ---: | ---: | --- |
| MDX | 293,809 | 4,985 | 词条 |
| 基础 MDD | 48 | 19 | 字体、CSS、jQuery、图片等 |
| `.1.mdd` | 162,679 | 13,347 | 160,805 MP3、1,872 PNG、2 JS |
| `.2.mdd` | 112,783 | 20,263 | 112,782 MP3、1 JS |

全部记录块类型均为 `2`，即 zlib。探针读取了 `hello`、`dictionary`、`running`、`apple` 的词条，验证实际 `sound://` 链接可定位 `.1.mdd` 的英美词语录音及 `.2.mdd` 的例句录音；读取资源时验证了解压长度与 ADLER32。系统 `afinfo` 识别一个 MP3 样本为单声道、22,050 Hz、约 2.247 秒，`afconvert` 成功将其解码为 49,536 帧、99,072 字节的 16-bit PCM。这证明了样本可读取和原生解码，尚未试听或渲染页面，也没有验证全部记录的完整性。

当前缺少可选的 `.3.mdd` 预生成 TTS 资源包，其 `oaldpex_tts.js` 不在现有三个 MDD 或外置文件中；主脚本检测到缺失会自动关闭该选项。已有正式词语与例句录音可继续使用；不能据此承诺任意无录音句子的离线合成发音。

## 读取与查词

MDX 保存键到文字记录的映射，MDD 保存资源路径到二进制记录的映射；两者具有键块、记录块及偏移索引。v2 使用 64 位长度和偏移，块可能不压缩、使用 LZO 或使用 zlib，不能仅凭版本号推断压缩方式。社区格式说明来自逆向，存在明确的不完整声明。[格式说明](https://github.com/zhansliu/writemdict/blob/master/fileformat.md)

读取器在后台打开 MDX 及同名 MDD 分卷，保留键索引和块索引；查询时定位记录范围，只读取并解压覆盖该范围的块。跨块记录按起止偏移拼接，不将两 GB 资源全部读入内存，也不先展开到磁盘。资源名处理 URL 百分号编码、正反斜杠与相对路径，外置文件仅从词库目录读取。该结构不等于已测得的延迟或内存承诺。

词条正文以 `@@@LINK=` 开头时继续查目标词，并限制重定向循环；页面的 `entry://` 是用户点击后的新查询。`mdictlib` 明确把重定向解析留给应用，GoldenDict 的实现也将其视为另一次查询。[mdictlib 接口范围](https://github.com/lonelam/mdictlib/tree/v0.2.8)、[GoldenDict 重定向实现](https://github.com/goldendict/goldendict/blob/master/mdx.cc)

zlib 块使用系统 libz 的解码与校验接口。Apple `COMPRESSION_ZLIB` 是 RFC 1951 raw DEFLATE，不能直接当作带头尾的 zlib stream 使用。解析层校验文件范围、整数溢出、声明解压尺寸与 ADLER32；不支持的版本、加密或压缩方式给出明确错误。[Apple 压缩格式](https://developer.apple.com/documentation/Compression/COMPRESSION_ZLIB)、[zlib 手册](https://www.zlib.net/manual.html)

## 解析器选型依据

| 方案 | 已核实能力及许可 | 对 Vellum 的取舍 |
| --- | --- | --- |
| 窄范围 Swift + 系统 libz（已采用） | 自行实现当前 v2 未加密格式；libz 有宽松许可。[zlib LICENSE](https://www.zlib.net/zlib_license.html) | 无新增运行时；当前格式范围能覆盖提供的词库。跨块、别名和坏文件需要持续测试，不能宣称通用 MDict 兼容。 |
| Rust `mdictlib` 0.2.8 + 小型 C ABI | MIT；文件与块按需读取，支持 v1/v2、常用文本编码、zlib、可选 LZO、v2 键索引及密码保护键头。LZO 依赖 `lzokay` 也是 MIT。仍由应用处理 HTML、分卷发现和重定向。[LICENSE](https://github.com/lonelam/mdictlib/blob/v0.2.8/LICENSE)、[接口](https://github.com/lonelam/mdictlib/blob/v0.2.8/src/lib.rs)、[lzokay LICENSE](https://github.com/encounter/lzokay-rs/blob/main/LICENSE) | 广格式支持时优先验证的候选；增加 Rust/C ABI、arm64/x86_64 构建和依赖许可清单。当前 Cargo 声明 Rust 1.97；固定版本后再验真实词库。[Cargo 配置](https://github.com/lonelam/mdictlib/blob/v0.2.8/Cargo.toml) |
| C++ `mdict-cpp` | 顶层 BSD-3-Clause，但仓库附带 GPL-2.0-or-later miniLZO；实际解析源码中的 LZO 分支仍未实现。[顶层许可](https://github.com/dictlab/mdict-cpp/blob/master/LICENSE)、[miniLZO](https://github.com/dictlab/mdict-cpp/blob/master/deps/minilzo/minilzo.c)、[解析实现](https://github.com/dictlab/mdict-cpp/blob/master/src/mdict.cc) | 不建议直接整体捆绑。首页许可与列出的能力不足以作为接入依据。 |
| Python `readmdict` / `mdict-utils` | `mdict-utils` 顶层 MIT，但实际 `base/readmdict.py` 具有 GPL-3.0 文件头。[文件许可](https://github.com/liuyug/mdict-utils/blob/master/mdict_utils/base/readmdict.py) | 可以做独立本机探针；发布时需处理实际文件许可、解释器及压缩依赖。每次查词启动 Python 也应避免。 |
| JavaScript `js-mdict` | 当前 v7 许可为 AGPL-3.0。[LICENSE](https://github.com/terasum/js-mdict/blob/master/LICENSE) | 不作为本次默认依赖；也不为了二进制解析另加 Node 运行时。 |

`mdictlib` 的这些能力是上游源码与文档声明，不是 Vellum 对此词库的验证结果。它默认跳过可选 checksum 校验，接入时应显式选择 `ChecksumPolicy::Verify`，并保留尺寸、范围和工作内存上限。其源代码快照为 `v0.2.8` / `520410ab2d4dc32b05030519f03e564b46ac80ca`。[校验策略与限制](https://github.com/lonelam/mdictlib/blob/v0.2.8/README.md)

## 页面与发音

独立词典 WebView 通过自定义 scheme 提供词条 HTML、MDD 资源和同目录 CSS/JS，统一资源入口与 MIME 类型。`WKURLSchemeHandler` 是 Apple 为本地自定义资源提供的接口；它接收每个资源请求，按 response、data、finish 顺序返回。内建 scheme 不能覆盖；任务取消后停止回调。[Apple 接口说明](https://developer.apple.com/documentation/webkit/wkurlschemehandler)、[WebKit scheme 配置契约](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebViewConfiguration.h)、[资源任务契约](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKURLSchemeTask.h)

不需要本地 HTTP 服务。`loadFileURL(_:allowingReadAccessTo:)` 能给外置文件目录读权限，但不能直接把 MDD 当作目录，因此自定义资源入口更统一。用导航代理接管 `entry://` 与 `sound://`，未知协议不交给外部应用。音频从正确 MDD 分卷读出后，用 `AVAudioPlayer(data:)` 播放并保留 player 生命周期；不依赖系统 TTS。是否能解码以真实音频格式为准。[文件读取规则](https://developer.apple.com/documentation/webkit/wkwebview/loadfileurl(_:allowingreadaccessto:))、[导航策略](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKNavigationDelegate.h)、[原生内存音频](https://developer.apple.com/documentation/avfaudio/avaudioplayer/init(data:filetypehint:))

页面交互保留原词典 JavaScript，原生接口仅用于词典查询与音频等必要操作。远程子资源和导航被阻止，词库脚本中的在线回退不可用。只拦截导航不足以阻止脚本、图片或 fetch 请求，资源策略需要覆盖这些入口。[Apple 资源规则](https://developer.apple.com/documentation/webkit/wkcontentruleliststore)、[WebKit 资源拦截说明](https://webkit.org/blog/3476/content-blockers-first-look/)

## 验收与限制

现有接入点是 `Sources/VellumCore/PDF/View/VellumPDFView.swift` 的 `explainDoubleClickedTextIfNeeded`；它已经在智能选词和鼠标结束后触发 AI。键盘查词应先于 `KeyboardController.swift` 的选区移动分支处理，并让 `VimKeyMap.swift` 保留大写 `K`，否则它会被归一化为向上滚动的小写 `k`。现有 AI WebView 使用固定 Markdown 模板，词典应有独立 WebView，复用浮层外观与定位方式。设置和帮助文字需同步更新 `GeneralSettingsView.swift`、`AppLanguage.swift` 和 `ShortcutCatalog.swift`；文稿目录权限说明位于 `scripts/package-app.sh`。项目发布包同时包含 arm64 和 x86_64，解析器或依赖也需覆盖两种架构。

验收覆盖选词触发、词条别名、分卷图片和字体、折叠/切换等 JavaScript 交互、自定义地址下的 `localStorage`、英美发音、关闭后停止播放及断网使用。性能需区分首次打开与重复查词，并观察后台索引期间主线程响应和峰值内存；目前没有本机应用端延迟承诺。解析层用小型自建 fixture 覆盖跨块记录、重定向循环、缺资源和损坏长度。

只读探针证明了样本记录与音频可读取、解码；该结果不能代替应用页面渲染、实际试听或完整词库兼容测试。通用 MDict 兼容、任意句子离线 TTS、多词典管理与全文检索均不在首版范围内。
