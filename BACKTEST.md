# RSI 离线回测

克隆本仓库后，用下面一条命令构建镜像并跑回测。K 线在 `data/BTCUSDT_data_30min.csv`（2021-01-01 至 2025-09-28，30 分钟，83086 根），构建时打进镜像，不需要再下载行情，也不需要 API 密钥。

Windows:

```bat
scripts\run_backtest.bat
```

Linux / macOS:

```bash
bash scripts/run_backtest.sh
```

脚本会启动已安装的 Docker（Windows 上若只有 WSL 里的 Docker，会自动用那一个），按顺序尝试拉取基础镜像，构建 `okx-sdk:backtest`，运行 `tests/rsi_backtest.py`，并核对输出。通过时退出码为 0，应看到：

- 每次张数 5.76
- K 线 83086 根
- 成交 590 笔
- 期末权益 16759.5685
- 最低权益 7649.6107
- 最大回撤 2998.1059

价格来自币安现货 BTCUSDT，盈亏按 OKX BTC-USDT-SWAP 每张 0.01 BTC 计算。没有手续费、资金费、滑点和强平。实盘程序不在这条命令里运行。

本机需要已经装好 Docker Engine 或 Docker Desktop。脚本不会安装 Docker 本身。
