# 会话记录

这份文件是 2026-10-02 这段 Cursor 会话的结论。Cursor 的聊天记录存在本机，换一台电脑登录同一个账号，侧栏里不会自动出现这段对话。代码和这份记录已经推到下面两个仓库，在另一台机器上克隆后可以直接读。

- GitHub：https://github.com/sanquzhuaibi/okx-sdk
- Cursor 托管：https://cursor.com/codebase/wanderzhao/okx-sdk （不公开，需要同一账号或在仓库页面授权）

本地原来的 `origin` 仍是上游 https://github.com/burakoner/okx-sdk ，没有改掉。

## 做成了什么

把原稿 RSI 策略做成了离线回测 `tests/rsi_backtest.py`，不向交易所下单。

规则与原稿一致：30 分钟收盘价，RSI 14（SMA，不是 Wilder），RSI ≥ 79 做多（21–22 点不做多），RSI ≤ 21 做空（0–12 点不做空），多单止损为收盘价 ≤ 开仓价的 90%，空单止损为收盘价 ≥ 持仓以来最低价的 103%。盈亏按 OKX `BTC-USDT-SWAP` 每张 0.01 BTC 计算。信号和成交都用同一根 K 线的收盘价。

K 线在 `data/BTCUSDT_data_30min.csv`，是币安现货 BTCUSDT 的 30 分钟数据，2021-01-01 至 2025-09-28，83086 根。不是 OKX 永续，也不是 10 年。

每次下单 5.76 张。这是按这段历史里 1 张最大回撤约 520.5 USDT，把最大回撤压在 3000 USDT 以内算出来的。实盘用的 `.env` 里 `PER_NUMBER=0.02` 没有改。5.76 是在同一段历史上拟合的，以后回撤可以超过 3000。

Docker 里实际跑通的结果：

- 每次张数 5.76
- K 线 83086 根
- 成交 590 笔
- 期末权益 16759.5685
- 最低权益 7649.6107
- 最大回撤 2998.1059

初始权益 10000 只用于显示，不参与下单数量。没有手续费、资金费、滑点、盘中止损和强平。约 590 笔吃单手续费会吃掉利润里不小的一块。

## 另一台机器怎么跑

先安装 Docker Engine 或 Docker Desktop，再克隆上面的 GitHub 仓库，然后：

```bat
scripts\run_backtest.bat
```

Linux / macOS：

```bash
bash scripts/run_backtest.sh
```

脚本会拉取基础镜像、构建 `okx-sdk:backtest`、跑回测并核对上面的数字。不需要 API 密钥。详细说明在 `BACKTEST.md`。

## 没有做完的部分

实盘脚本 `tests/rsi_trading_bot.py` 没有在本机或 Docker 里跑通，也没有放进这次上云的提交。密钥只留在本机、被 git 忽略的 `.env.local`，不要提交。旧文档里曾经出现过明文密钥，应在 OKX 后台作废并重新生成。

## 和原稿“涨了好几倍”的关系

原稿和 VeighNa 笔记本按大约 1 BTC 的价格盈亏来算。同一条成交路径放到 1 BTC（100 张）上，峰值权益大约 13.58 倍，但中途权益会到大约 -30805，笔记本因此记成爆仓、收益率 0。5.76 张是为了把这段历史上的最大亏损限制在 3000 USDT，所以期末大约 1.68 倍，不是原稿那个未计爆仓的倍数。
