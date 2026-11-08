# 波点歌词 · Bodian Lyrics

为 macOS 版波点音乐制作的独立状态栏歌词应用，支持简体中文和英语。

## 功能

- 状态栏显示当前歌词，支持逐字高亮、居中或右对齐换行、字体选择和位置微调。
- 没有歌词时显示歌名和歌手。没有歌曲时显示静态声波。
- 可从设置或状态栏菜单调整当前歌曲的歌词时间，每次调整 100 毫秒，偏移按歌曲保存在本机。
- 启用歌词后台后，应用可随波点音乐启动和退出。「设置 → 通用」提供后台重启和已解码歌词文件夹入口。

## 安装

需要 Apple 芯片 Mac 和 macOS 14 或更新版本。

1. 从 [GitHub Releases](https://github.com/Taulee/BodianLyrics/releases/latest) 下载 DMG，把 `BodianLyrics.app` 拖到「应用程序」。
2. 打开 App，在「设置 → 通用」点「启用歌词后台」。如果 macOS 要求授权，在登录项设置里允许波点歌词在后台运行。

发布包采用临时签名，未经 Apple 公证。macOS 若拦截首次打开，可在「系统设置 → 隐私与安全性」查看这次拦截。

## 本地数据

后台通过 MediaRemote 读取波点音乐的播放信息，只读查询波点的 `database/songDB.db` 来匹配歌曲，并解析 `~/Library/Caches/cn.wenyu.bodian.bodianPc/cache/lyric/` 中的歌词。解析结果保存在 `~/Library/Application Support/Bodian Lyrics/Parsed/`。当源文件更新时，后台会重建对应的缓存。

前台监听本地播放状态文件和已解码歌词目录。正常播放时，后台每隔数秒写入播放状态，界面在两次更新之间连续推进歌词。

## 编译

需要 Swift 和 macOS SDK。运行 `./build.sh` 会编译并临时签名 App，在 `dist/` 生成 DMG。可传入版本号，例如 `./build.sh 1.0.0`。

- `Sources/BodianLyrics/` 包含设置界面和状态栏歌词。
- `Sources/BodianCore/` 包含歌词排版、逐字填色和播放进度计算。
- `Sources/BodianEngine/` 包含播放状态读取和本地歌词解析。
- `native/` 和 `packaging/` 包含媒体状态桥接和后台服务配置。

## 许可证

本项目按 GNU GPL v3 分发，包含 [Lyrimuse](https://github.com/Yudaotor/lyrimuse) 的代码。授权条款和署名见 [LICENSE](LICENSE)。
