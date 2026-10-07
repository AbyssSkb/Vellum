# Vellum

[English](README.md) | 简体中文

**一款让你专注于页面的原生 macOS PDF 阅读器。**

Vellum 将平滑的 Vim 风格导航、键盘目录与沉浸画廊放进安静、紧凑的阅读界面。使用 SwiftUI、AppKit 与 PDFKit 构建。

[下载 macOS 版本](https://github.com/AbyssSkb/Vellum/releases/latest) · [使用指南](docs/USER_GUIDE.zh-CN.md) · [反馈问题](https://github.com/AbyssSkb/Vellum/issues)

![Vellum 阅读画布、紧凑标签栏与标注颜色选择](docs/images/vellum-reader.png)

## 按自己的节奏阅读

点按或按住 `j`、`k` 平滑滚动。适合整页或宽度、连续缩放、通过 `12G` 跳到指定页，再用 `Control-O`、`Control-I` 返回阅读轨迹。鼠标选中文本后，也能通过键盘按行或词调整选区。

紧凑标签栏让多个文档随时可达。`T` 打开可搜索的文件列表，大幅预览各文档上次阅读的页面，按 `Enter` 继续阅读选中的文件。`X` 恢复最近关闭的文件。每个文件只占一个标签页，重新打开已更新的 PDF 会加载最新内容。过长的标签标题只在打开、切换或悬停时滚动一轮。

## 需要时，打开文档地图

按 `t` 显示或隐藏目录。短按 `Tab` 在正文与目录之间切换键盘焦点，目录隐藏时会先打开它。通过 `j`、`k` 浏览，`h` 折叠，`l` 展开，按 `Enter` 跳转并回到正文阅读。目录还支持 Vim 的 `zo`、`zc`、`zO`、`zC`、`zr`、`zm`、`zR`、`zM`，以及递归折叠与数字前缀。目录打开时也能使用 `H`、`L` 切换文件。

![Vellum 的多级目录、阅读页面与标签栏](docs/images/vellum-outline-tabs.png)

## 看见前后页面

长按 `Tab` 进入沉浸画廊。当前页以大幅预览呈现，前后页面分列两侧。使用 `h` / `l` 前后移动一页，`k` / `j` 前后移动三页。松开 `Tab` 阅读选中页，按 `Esc` 返回进入前的位置。

![沉浸画廊中的当前页与相邻页面](docs/images/vellum-gallery.png)

## 留下有用的内容

使用 `/` 搜索，`n`、`N` 切换结果，`v` 将结果转为选区。`y` 复制，`m` 高亮，共有五种标注颜色。标注自动保存到 PDF；文件无法保存或已被外部修改时，应用提供恢复选项。

![PDF 搜索、匹配高亮与结果计数](docs/images/vellum-search.png)

*截图使用此[示例 PDF](docs/samples/the-shape-of-attention.pdf)。*

## 实验性 AI

AI 辅助是可选的实验性功能。配置与使用方法请见[使用指南](docs/USER_GUIDE.zh-CN.md#实验性-ai)。

## 开始使用

1. 从 [Releases](https://github.com/AbyssSkb/Vellum/releases/latest) 下载最新 DMG，将 Vellum 拖入 Applications。
2. 使用 `o` 或 `Command-O` 打开 PDF；`O` 在新标签页打开文件。
3. 按 `z` 适合宽度，或 `0` 适合整页，然后通过 `j`、`k` 阅读。

| 按键 | 操作 |
| --- | --- |
| `j` / `k`、`d` / `u` | 向下 / 向上滚动；`d` / `u` 步幅更大 |
| `Space` / `f`、`b` | 下一页 / 上一页 |
| `gg`、`G`、`12G` | 首页、末页、第 12 页 |
| `=` / `-`、`0`、`z` | 放大 / 缩小、适合整页、适合宽度 |
| `t` | 显示或隐藏目录 |
| 短按 `Tab` | 在正文与目录之间切换焦点 |
| 长按 `Tab` | 打开沉浸画廊 |
| `H` / `L`、`T` | 上一个 / 下一个标签；可搜索的标签切换器 |
| `/`、`n` / `N` | 搜索；下一个 / 上一个结果 |
| `m`、`c`、`y` | 高亮、切换标注颜色、复制 |

字母快捷键作用于当前获得焦点的阅读区域。完整的选区操作、目录折叠、焦点行为与快捷键请见[使用指南](docs/USER_GUIDE.zh-CN.md)。

## 偏好与更新

设置支持中英文界面、默认文件打开方式、初始页面适配、标注颜色、可选的会话恢复以及 AI 配置。恢复上次标签页默认关闭。

自动更新由 Sparkle 处理，检查默认开启。新版本会在后台下载并准备，随后可以选择立即重启更新，或在正常退出应用时安装。通过 Vellum 菜单或通用设置手动检查，也使用同一个更新窗口，支持 Vim 风格的更新说明滚动，按钮旁会显示字母快捷键。详见[更新操作](docs/USER_GUIDE.zh-CN.md#设置和更新)。

## 从源码构建

需要 macOS 14 或更新版本，以及 Swift 6.2 工具链。发布包支持 Apple silicon 与 Intel Mac。

```sh
git clone https://github.com/AbyssSkb/Vellum.git
cd Vellum
swift test --no-parallel
scripts/package-app.sh
open dist/Vellum.app
```

打包脚本会在 `dist/Vellum.app` 生成通用 macOS 应用。

## 反馈

欢迎通过 [GitHub Issues](https://github.com/AbyssSkb/Vellum/issues) 报告问题或提出建议。遇到渲染、导航问题时，请附上 macOS 版本、复现步骤，以及可以公开分享的示例 PDF。
