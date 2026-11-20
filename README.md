# DeskQuote for macOS

<img src="Resources/AppIcon-1024.png" width="96" alt="DeskQuote 应用图标">

DeskQuote 是一个 macOS 桌面自选行情窗。用小窗看现价、涨跌和 1 分钟 K 线，点开卡片查看行情详情。支持 Apple Silicon 和 Intel，提供 Universal 2 安装包。

[下载安装包](https://github.com/Fu-Fu-Fu-Fu/deskquote-mac/releases/latest) · [版本记录](CHANGELOG.md)

## 安装

1. 在 Releases 下载 `StockBar-版本号.dmg`，把里面的 `StockBar.app` 拖入「应用程序」。
2. 打开应用。桌面行情窗和菜单栏图标会出现。窗口隐藏后，从菜单栏图标选择「显示或隐藏桌面行情」。
3. 安装包使用临时签名。首次打开若被 macOS 拦截，可在「系统设置 → 隐私与安全性」确认来源后选择「仍要打开」。

已有本地改版用户可以先退出应用，再替换 `StockBar.app`。应用通过同一个本机偏好设置域读取自选、分组、排序和窗口位置。

## 使用

- 在主屏幕拖动窗口顶部可调整位置。「置顶」可让行情窗跨桌面悬浮。
- 点击「＋」添加自选，可用代码（例如 `AAPL`、`0700.HK`、`600519`）或内置品种名（例如「浙商黄金」）。按住卡片上下拖动可排序，右键可移除。
- 小窗每 5 秒检查报价。「＋」右边的「刷新」可立即检查，底部会显示完成时间。
- 卡片显示 1 分钟 K 线，当前蜡烛随报价更新。点击卡片查看分钟图和日线。左右拖动浏览历史，滚轮缩放，点击「回到最新」恢复跟随行情。鼠标移到 K 线上查看开、高、低、收及较上一交易日收盘的涨跌额和涨跌幅，行情源提供昨结时会标明。历史 K 线使用对应交易日的基准。可浏览的历史长度取决于数据源。
- 菜单栏也可以查看 A 股和场内基金、按名称或拼音缩写搜索、管理分组和开启登录启动。

## 行情源

| 默认品种 | 代码 | 来源 |
| --- | --- | --- |
| 纳斯达克 100 指数 | `^NDX` | Yahoo 财经 |
| 纳指 E-mini 期货 | `NQ=F` | Yahoo 财经，源端约延迟 10 分钟 |
| 伦敦金现货 | `XAUUSD` | 新浪财经 |
| 纳指期货 CFD | `NQ-CFD` | 新浪财经 |
| 浙商银行积存金 | `CZB-GOLD` | 京东金融，客户买入价 |
| 上证指数 | `SH000001` | 新浪财经 |
| 科创 50 指数 | `SH000688` | 新浪财经 |

卡片显示源端报价时间。5 秒是应用的查询频率，实际报价和 K 线的时效取决于行情源。行情请求只向对应的数据源发送品种代码，添加自选无需账号或 API Key。菜单栏行情使用腾讯财经和东方财富，名称搜索会将关键词发送至搜索源。

## 构建与测试

需要 macOS 和 Apple Command Line Tools，无第三方代码依赖。

```sh
make            # 构建 build/StockBar.app
make test       # 离线测试，包括分钟 K 线合并与自选代码映射
make ui-test    # AppKit 测试，需要图形会话
make release    # 在 dist/ 生成 DMG 和 SHA256SUMS
```

如系统默认选择了预览版 SDK，可为构建显式指定已安装的稳定 SDK。例如，本项目使用 macOS 26.5 SDK 验证：

```sh
SDKROOT="$(xcrun --sdk macosx26.5 --show-sdk-path)" make
```

`Sources/` 是应用代码，`Resources/` 是应用资源，`Tests/` 包含离线及在线测试。安装包附带 SHA-256 校验文件，在两个文件所在目录运行 `shasum -a 256 -c SHA256SUMS` 即可校验。

## 来源与许可

DeskQuote 基于 TalonZhang 的 [StockBar v0.7.2](https://github.com/TalonZhang/stockbar/tree/v0.7.2) 开发，保留上游提交历史、图标和 [MIT 许可](LICENSE)。菜单栏的分组、搜索和 Touch Bar 说明见 [上游使用文档](https://github.com/TalonZhang/stockbar/blob/v0.7.2/README.md)。
