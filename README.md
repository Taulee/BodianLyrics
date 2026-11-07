# 波点歌词 · Bodian Lyrics

波点歌词是为 macOS 版波点音乐制作的独立歌词应用。界面支持简体中文和英语。

## 功能

- 灵动岛和状态栏显示歌词。
- 设计上由用户的 LaunchAgent 保持后台运行，使界面可随波点音乐启动和退出。手动退出界面后，下次打开波点仍可唤起。

## 安装

从 [Releases](https://github.com/Taulee/BodianLyrics/releases) 下载 Apple 芯片版 ZIP 并解压。在解压出的目录运行 `bash install.sh`。脚本将 App 安装到 `~/Applications`，为当前用户启动后台服务，再打开设置。升级前先从状态栏退出波点歌词。

发布包采用临时签名，未经 Apple 公证。macOS 若拦截首次打开，可在「系统设置 → 隐私与安全性」里查看这次拦截并选择是否允许。

## 本地数据

后台通过 MediaRemote 读取波点音乐的歌名、歌手、播放进度和封面。它从波点的 `database/songDB.db` 只读查找歌曲 ID，并监听 `~/Library/Caches/cn.wenyu.bodian.bodianPc/cache/lyric/` 中的歌词文件。波点提前写入后续歌曲的缓存时，后台也会提前解析。

解析结果保存在 `~/Library/Application Support/Bodian Lyrics/Parsed/<歌曲 ID>.json`。播放时按 ID 直接读取。源文件修改时间或大小发生变化时，同一 ID 的结果会更新。波点清除源文件后，已解析结果仍可复用。原文、译文和封面全部来自本机。

## 源码与编译

| 目录 | 职责 |
| --- | --- |
| `Sources/BodianLyrics/` | SwiftUI 设置、状态栏、灵动岛和播放状态接入 |
| `Sources/BodianCore/` | 分句、逐字填色、进度外推和屏幕几何 |
| `engine/` | Go 后台、播放状态和歌词缓存 |
| `native/` | Objective-C MediaRemote 桥接和 Perl 入口 |

界面最低部署目标为 macOS 14。编译需要 Swift、Go 1.24 和 macOS SDK。`./build.sh 0.1.0` 会按当前 Mac 的架构构建并签名，ZIP 输出到 `dist/`。解压 ZIP 后可用同一个安装脚本。

## 许可证

本项目按 GPL-3.0 分发。界面基础、分句和逐字时间代码源自 [Lyrimuse](https://github.com/Yudaotor/lyrimuse)，保留原作者与贡献者署名。许可证全文见 [LICENSE](LICENSE)。
