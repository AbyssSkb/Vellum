# PDF 模糊搜索打开方案

调研与实现日期：2026-10-25。本文记录首版本地预览的实现和选型依据；应用端性能目标仍需实测验收。

## 结论

采用原生 `NSMetadataQuery` 在后台维护当前用户主目录（`~/`）下的 Spotlight 文件清单，按扩展名 `.pdf` 过滤（大小写不敏感，兼容 `.PDF`），缓存路径快照，再交给本机 fzf 过滤。搜索窗口直接读取已有快照，输入时只做匹配，不重新收集文件。

按 `Z`（`Shift-Z`）从正文、目录或空窗口打开原生搜索浮层，也可使用文件菜单中的“快速打开 PDF”。首版只搜索文件名和路径，回车通过现有 PDF 打开流程进入阅读器。小写 `z` 继续适合宽度，目录的 `zo` / `zc` 等折叠组合保留。保留系统打开对话框；不增加自建持久索引、下载目录扫描、目录监听服务或全文搜索。

## 本机实测

环境为本机 Mac16,12、16 GiB 内存、macOS 27.0.1，fzf 0.74.3、fd 10.4.2。枚举方案各串行执行 5 次并轮换命令顺序；匹配每种查询执行 9 次。保留现有文件系统和 Spotlight 缓存，没有清空系统缓存或重启；所有数字都是此次运行的观测，不能称为冷启动保证。

### 收集完整清单

下表为中位数，括号内是最小值到最大值，单位均为毫秒。常用目录是 `~/Documents`、`~/Downloads`、`~/Desktop` 的合并范围。

| 方案 | 常用目录：414 个 PDF | 整个用户目录 | 用户目录候选数 |
| --- | ---: | ---: | ---: |
| `mdfind` | 38（38–38） | 151（137–161） | 501 |
| 原生 `NSMetadataQuery` | 36（34–59） | 44（44–47） | 501 |
| `fd --hidden --no-ignore` | 126（122–294） | 2,536（2,389–2,858） | 519 |
| `/usr/bin/find` | 473（467–479） | 超过 20,000，5 次均超时 | 330，仅为超时前部分结果 |
| fzf 内置 walker | 126（125–128） | 4,241（3,417–4,722） | 519 |

命令行耗时包含子进程启动、收集输出和退出。原生 API 以 `start()` 到完成回调中生成 NUL 路径快照计时，代表已运行应用内的调用成本，不包含独立 Swift 探针的启动和 RunLoop 退出等待。API 的计时已包括取路径和序列化。该结果支持原生接入，但不能证明在其他机器或冷缓存下总是更快。

常用目录中，四种枚举方式的路径集合完全一致。整个用户目录中，`fd` 与 walker 的集合一致；Spotlight 与扫描相比有 19 个仅扫描返回、1 个仅 Spotlight 返回的路径。Spotlight 按内容类型查询，扫描按扩展名查询；索引、权限、符号链接和元数据差异均可能影响覆盖，不能把数量差直接等同于漏搜。另以文件名扩展名查询 Spotlight，结果集合数量仍为 501，没有消除该差异。`find` 超时结果不参加覆盖比较。

### 本地索引卷与首批结果

全机查询只测 Spotlight 两种入口，不把全机结果与用户目录扫描混作同一范围。这是历史选型和压力测试数据；首版已按用户要求限定为主目录范围，本机历史查询为 501 个候选。

| 入口 | 候选数 | 首批到达中位数 | 完整清单中位数 | 完整清单范围 |
| --- | ---: | ---: | ---: | ---: |
| `mdfind` 默认索引范围 | 13,834 | 159 ms | 191 ms | 190–1,079 ms |
| 原生 `NSMetadataQueryLocalComputerScope` | 13,834 | 25 ms | 182 ms | 179–228 ms |

命令行首批指 stdout 实际收到第一个 NUL，受输出缓冲影响；原生首批指首次非空 gathering 通知。它们不是同一种内部事件。两个范围在本机此次查询的数量一致，不代表在任意挂载环境下作用域完全相同。

13,834 个路径生成的 NUL 数据为 1,098,236 字节，约 1.05 MiB；原生快照构建中位数为 32.5 ms，应在后台完成。将原生通知批处理间隔从默认 1 秒改为 50 ms 后，完整清单中位数为 182 ms，基本没有改善；保留默认值。默认更新批处理间隔不等于初始查询必等 1 秒。

之前单次观测约 1.4 秒，此次 `mdfind` 也出现约 1.08 秒。不能依赖“通常两百毫秒”把清单查询放进每次唤起或键入的等待路径。

### 已缓存清单的匹配

调用 `fzf --read0 --print0 --scheme=path --filter=<query>`，从进程启动到完整取回结果计时，包含输入输出传输。各查询中位数如下：

| 缓存候选数 | `attn` | `pdf`（返回全部候选） | `中文` | `2024` |
| --- | ---: | ---: | ---: | ---: |
| 501 | 3.5 ms | 3.6 ms | 3.0 ms | 3.3 ms |
| 13,834 | 10.9 ms | 14.1 ms | 4.5 ms | 5.0 ms |

这组数据中所有匹配的单次耗时为 2.8–14.6 ms。与首版主目录范围对应的 501 条清单，各查询中位数约为 3–4 ms；13,834 条清单保留为压力数据。首版使用本机 fzf 子进程过滤，不移植 fzf 算法或维护常驻交互终端。文件清单收集在后台进行。窗口首帧和完整键入到绘制延迟仍需在原生应用中验证。

### 本机复现

基准脚本和不含实际文件名的原始计时位于本工作区的 `.build/pdf-quick-open-benchmark/`，该目录由 Git 忽略；本文保存可供后续比较的汇总。`benchmark.py` 自检覆盖扩展名大小写、中文、空格、换行和排除同名目录。脚本固定使用当前 Homebrew 路径，其他机器复用时先调整工具路径。扫描的 stderr 不收录到结果中，非零退出和超时必须标为不完整。

同一用户目录的关键命令：

```sh
mdfind -0 -onlyin "$HOME" 'kMDItemContentTypeTree == "com.adobe.pdf"'
fd --hidden --no-ignore --type f --extension pdf --print0 . "$HOME"
find -P "$HOME" -type f -iname '*.pdf' -print0
```

walker 需在 TTY 输入下测试，清除 `FZF_DEFAULT_COMMAND`、`FZF_DEFAULT_OPTS`、`FZF_DEFAULT_OPTS_FILE` 后运行：

```sh
fzf --walker=file,hidden --walker-skip= --walker-root "$HOME" \
  --scheme=path --filter='.pdf$' --print0
```

walker 保留默认排序，因此 stdout 首批通常要等完整枚举；其总耗时包含扩展名过滤和排序。没有用其首批时间推断内部遍历何时找到第一个文件。以上观测不能保证所有目录的文件均可访问。

## 文件清单来源

`NSMetadataQuery` 有初始收集与持续更新两个阶段，使用初始完成通知区分“仍在加载”和“结果已齐”。持续更新可维护内存清单，无需再引入目录监听。`mdfind` 是同一类元数据查询的命令行入口；普通调用是一次结果，`-live` 手册描述为持续更新匹配数量。原生 API 的主要收益是结构化结果、生命周期与结果通知，不能由此推断它的初始查询一定更快。[Apple 文件元数据查询说明](https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/SpotlightQuery/Concepts/QueryingMetadata.html)、[本机 Apple mdfind 手册](/usr/share/man/man1/mdfind.1)

搜索范围设为当前用户主目录 URL，只返回 `~/` 下的已索引文件。首版不使用全机或本地卷作用域；主目录以外的文件仍可通过系统文件对话框打开。

macOS 文件夹权限会限制 GUI 应用可见的 Spotlight 结果。此次复现中，终端能找到 `Documents/AI/DeepSeek-V2.pdf`，独立 GUI 应用的原生查询、底层查询和 `mdfind` 子进程均只返回 59 个候选，文稿目录结果为零；不能用终端的 501 个候选证明应用有相同覆盖。快速打开提供“文件夹访问…”菜单，由用户选择文稿、下载或桌面后，在后台读取一次对应目录以请求系统权限，成功后重启原有查询。该操作不递归扫描，也不改变主目录与 PDF 后缀限制。打包时提供中英文权限用途说明；拒绝权限保留已有结果并提示系统设置入口。[Apple 文件夹权限说明](https://developer.apple.com/documentation/bundleresources/information-property-list/nsdocumentsfolderusagedescription)

PDF 条件使用 `kMDItemFSName` 的 `.pdf` 后缀，大小写不敏感，不使用 UTI 内容类型匹配。清单更新具有延迟，新下载的 PDF 可能暂时搜不到；文件也可能在选中前被移动或删除，最终打开仍交给现有文件校验和错误提示处理。用户排除的 Spotlight 目录不承诺可搜到，可通过原有系统文件对话框直接打开。[Apple Spotlight 隐私设置](https://support.apple.com/guide/mac-help/prevent-spotlight-searches-in-files-mchl1bb43b84/mac)

直接扫描适合用户明确指定少数文档目录的场景。`fd` 默认跳过隐藏项与 ignore 规则；此次基准统一启用 `--hidden --no-ignore`，以减少范围差异。它支持类型、扩展名、绝对路径和 NUL 输出。[fd 官方手册](https://raw.githubusercontent.com/sharkdp/fd/master/doc/fd.1)

fzf 的 walker 只在标准输入为 TTY 且没有 `FZF_DEFAULT_COMMAND` 时启用。GUI 把清单通过管道传入后，walker 不参与；以空管道测量 walker 会得到错误结论。[fzf 输入来源实现](https://github.com/junegunn/fzf/blob/master/src/reader.go)

## 首版运行流程

1. 主窗口出现、阅读会话恢复后，启动一个 `NSMetadataQuery`，将 `searchScopes` 设为当前用户主目录 URL，条件为 `kMDItemFSName ENDSWITH[c] '.pdf'`。将查询通知及快照构建放在专用串行 `OperationQueue`，以 utility 优先级运行；在该队列启动查询。缓存 URL 清单及序列化的 NUL 数据，主线程只接收供界面展示的快照。
2. `Z`（`Shift-Z`）或文件菜单中的“快速打开 PDF”打开原生浮层并立即聚焦输入框。空查询先显示已有清单的前若干项；首次查询尚未完成时显示加载状态，窗口与输入保持可用。
3. 初始收集时可先发布第一批非空结果，再在收集完成时替换为完整快照；收集中继续显示加载状态，避免把暂时没有匹配误报为最终无结果。之后消费系统的增删改通知。快照更新后，针对当前文本重新匹配。选中文件以 URL 为身份，避免列表更新使同一行序号指向另一份 PDF。
4. 文本变化后异步调用 fzf，只保留最新匹配任务。任务带文本及清单代次；已过期的输出即使成功返回也不得覆盖新结果。先不加人为输入等待，若原生键入验证表明有必要再合并连续任务。关闭浮层立即取消匹配并恢复原阅读焦点。界面用惰性列表展示结果，避免一次创建全部候选行。
5. 回车按现有默认打开模式打开选中 URL，成功后关闭浮层。空结果时回车无动作。缺少 fzf 时在浮层提示 `brew install fzf`，并提供现有系统打开入口。

保留 query 对象并消费更新通知，退出应用时停止。文件清单通过系统通知持续刷新，不额外设定重复扫描定时器；默认通知批处理允许轻微更新延迟。读取 live 查询结果前调用 `disableUpdates()`，在 `defer` 中 `enableUpdates()`，确保读取期间结果稳定；快照替换与匹配使用不可变副本。查询失败保留上次有效快照并显示状态。首版只做内存缓存，应用重启后重新后台收集；刚启动就搜索时可能先看到加载状态。[Apple live 查询结果读取](https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/SpotlightQuery/Concepts/QueryingMetadata.html)

`NSMetadataQuery.operationQueue` 支持指定通知和 delegate 调用队列；`start()` 应在该队列或主线程调用。该能力兼容项目的 macOS 15 最低版本。[Apple 查询操作队列](https://developer.apple.com/documentation/foundation/nsmetadataquery/operationqueue)、[Apple 开始查询](https://developer.apple.com/documentation/foundation/nsmetadataquery/start())

## fzf 调用边界

使用 `Process.executableURL` 和 `arguments` 数组直接启动已确认可执行的 fzf，查询作为一个 `--filter` 参数传递。按常见 Homebrew 安装目录及应用继承的 PATH 查找二进制，不通过登录 shell 解析用户配置。`Process` 参数不会经过 shell 展开。[Apple Process 参数](https://developer.apple.com/documentation/foundation/process/arguments)

调用形态为 `fzf --read0 --print0 --scheme=path --filter <query>`。输入、输出均按 NUL 拆分，保留文件名中的空格、中文、制表符和换行。显式使用路径评分，因为管道输入默认不是路径评分。过滤为一次非交互操作；退出码 1 表示无匹配，2 表示错误。首版只使用排序后的路径，不自行重写 fzf 的评分或解析终端高亮。[fzf 官方手册](https://raw.githubusercontent.com/junegunn/fzf/master/man/man1/fzf.1)

清除子进程的 `FZF_DEFAULT_OPTS`、`FZF_DEFAULT_OPTS_FILE` 和 `FZF_DEFAULT_COMMAND`，避免个人终端配置改变应用输出协议。Foundation 默认继承应用环境，修改必须在启动前完成。输入写入和 stdout/stderr 读取在后台并行推进，完成后关闭输入；避免大清单填满管道，也避免在主线程等待子进程退出。[Apple Process 环境](https://developer.apple.com/documentation/foundation/process/environment)、[Apple Process](https://developer.apple.com/documentation/foundation/process)

## 接入范围与验证

文件清单与匹配状态、原生浮层接入以下现有入口：

- `Sources/Vellum/App/AppEntry.swift`：增加“快速打开 PDF”菜单，保留 `⌘O`。
- `Sources/VellumCore/Input/VimKeyMap.swift`：`Z`（`Shift-Z`）打开浮层，小写 `z` 适合宽度，目录折叠组合保持原有行为。
- `Sources/VellumCore/Views/Reader/ContentView.swift`：挂载浮层，包含未打开文档的空状态。
- `Sources/VellumCore/Stores/AppState.swift`、`AppState+Reader.swift`：浮层状态、互斥展示和焦点保存恢复。
- `Sources/VellumCore/Stores/AppState+Tabs.swift`：复用 `openInCurrentTab` / `openInNewTabs` 和 `AppPreferences.defaultPDFOpenMode()`。
- `Sources/VellumCore/Views/Components/ListSearchField.swift`、`Sources/VellumCore/Views/Reader/TabSwitcherOverlay.swift`：复用上下、回车、Esc、输入法处理与文件名/目录行样式，按需要读取和调用。
- `Sources/VellumCore/App/AppLanguage.swift`：提供中英文文案。
- `Sources/VellumCore/Views/Settings/ShortcutCatalog.swift`、README 与用户指南：同步 `Z` 快捷键、fzf 依赖和索引限制。

针对新增状态与进程边界做小而明确的测试：NUL 路径往返、无匹配和异常退出、缺少 fzf、快速输入丢弃旧结果、关闭取消、中文输入法确认、空窗口打开、重复文件复用已有 tab。用少量临时 PDF 验证增删改更新；Spotlight 索引时序的集成测试设超时并与纯匹配测试分开。打开流程中的未保存标注保护继续走原有逻辑。

本地交付先运行 `scripts/test.sh --filter` 的相关检查，再通过全新应用名称和 bundle identifier 运行 `scripts/package-app.sh`，打开独立预览验证焦点、结果更新和阅读连续性。只有用户完成本地测试确认后才发布。

性能验收目标：已有快照时，唤起浮层与输入聚焦在 50 ms 内完成；以本机主目录清单（历史查询约 501 条）连续输入时，最终文本到结果绘制在 80 ms 内完成。13,834 条全机清单作为额外压力测试，不代表首版搜索范围。两项都是实现目标，目前尚未测到应用端数据。加载、刷新和快照序列化不得阻塞主线程；查询未完成时浮层保持可输入、可取消。
