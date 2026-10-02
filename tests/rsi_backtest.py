"""
OKX RSI 策略离线回测。

规则与 tests/mian123111.py 一致：30 分钟收盘价、RSI 14、79/21 开仓、
21–22 点不做多、0–12 点不做空、做多止损 10%、做空止损 3%。
盈亏按 BTC-USDT-SWAP 每张 0.01 BTC 计算，不向交易所下单。
"""

import argparse
import os
import sys

import pandas as pd

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_CSV = os.path.join(ROOT_DIR, 'data', 'BTCUSDT_data_30min.csv')
CT_VAL = 0.01
INITIAL_EQUITY = 10000.0
# 在 2021-01-01 至 2025-09-28 的 30 分钟数据上，1 张的最大回撤约 520.5 USDT。
# 5.76 张把最大回撤压在 3000 USDT 以内。再加大就会超过这个亏损上限。
# 实盘 .env 的 PER_NUMBER 不在这里改。
BACKTEST_CONTRACTS = 5.76
RSI_WINDOW = 14


def read_env_file(env_path):
    values = {}
    if not os.path.isfile(env_path):
        return values
    with open(env_path, encoding='utf-8') as env_file:
        for raw_line in env_file:
            line = raw_line.strip()
            if not line or line.startswith('#') or '=' not in line:
                continue
            name, value = line.split('=', 1)
            name = name.strip()
            value = value.strip().strip('"').strip("'")
            if name and not (value.startswith('${') and value.endswith('}')):
                values[name] = value
    return values


def load_public_config():
    config = read_env_file(os.path.join(ROOT_DIR, '.env'))
    swap_name = config.get('SWAP_NAME', 'BTC-USDT-SWAP')
    per_number = float(config.get('PER_NUMBER', '0.02'))
    return swap_name, per_number


def load_csv(path):
    frame = pd.read_csv(path)
    if 'timestamp' in frame.columns and 'c' in frame.columns:
        stamps = pd.to_datetime(frame['timestamp'])
        closes = pd.to_numeric(frame['c'])
    elif 'open_time' in frame.columns and 'close' in frame.columns:
        stamps = pd.to_datetime(frame['open_time'])
        closes = pd.to_numeric(frame['close'])
    else:
        raise SystemExit('CSV 需要 timestamp/c 或 open_time/close 列')

    data = pd.DataFrame({'timestamp': stamps, 'close': closes})
    data = data.dropna().sort_values('timestamp')
    data = data.drop_duplicates('timestamp')
    return data.reset_index(drop=True)


def download_history(inst_id, bar, pages):
    from okx.restapi import MarketDataClient

    client = MarketDataClient()
    rows = []
    after = ''
    for _ in range(pages):
        result = client.get_history_candlesticks(
            instId=inst_id, bar=bar, after=after, limit='100'
        )
        batch = result.get('data') if isinstance(result, dict) else None
        if not batch:
            break
        rows.extend(batch)
        after = batch[-1][0]
        if len(batch) < 100:
            break
    if not rows:
        raise SystemExit('没有下载到 K 线')

    frame = pd.DataFrame(rows)
    stamps = pd.to_datetime(pd.to_numeric(frame[0]), unit='ms')
    closes = pd.to_numeric(frame[4])
    data = pd.DataFrame({'timestamp': stamps, 'close': closes})
    return data.drop_duplicates('timestamp').sort_values('timestamp').reset_index(drop=True)


def add_rsi(data):
    delta = data['close'].diff()
    gain = delta.clip(lower=0).rolling(window=RSI_WINDOW).mean()
    loss = (-delta.clip(upper=0)).rolling(window=RSI_WINDOW).mean()
    rs = gain / loss
    data = data.copy()
    data['rsi'] = 100 - (100 / (1 + rs))
    return data


def in_long_blackout(stamp):
    return 21 <= stamp.hour <= 22


def in_short_blackout(stamp):
    return 0 <= stamp.hour <= 12


def run_backtest(data, per_number):
    position = 0
    can_long = True
    can_short = True
    min_price = 0.0
    open_price = 0.0
    cash = INITIAL_EQUITY
    peak = INITIAL_EQUITY
    max_drawdown = 0.0
    min_equity = INITIAL_EQUITY
    trades = 0

    def mark_equity(price):
        if position == 1:
            unrealized = (price - open_price) * per_number * CT_VAL
        elif position == -1:
            unrealized = (open_price - price) * per_number * CT_VAL
        else:
            unrealized = 0.0
        return cash + unrealized

    def realize(price, closed_side, size):
        nonlocal cash
        if closed_side == 1:
            cash += (price - open_price) * size * CT_VAL
        else:
            cash += (open_price - price) * size * CT_VAL

    for row in data.itertuples(index=False):
        rsi = row.rsi
        price = float(row.close)
        if pd.isna(rsi) or rsi != rsi:
            continue

        if position == -1 and price < min_price:
            min_price = price

        if rsi >= 79 and not in_long_blackout(row.timestamp):
            can_short = True
            if position == 0 and can_long:
                position = 1
                open_price = price
                trades += 1
            elif position == -1 and can_long:
                realize(price, -1, per_number)
                position = 1
                open_price = price
                trades += 1

        if rsi <= 21 and not in_short_blackout(row.timestamp):
            can_long = True
            if position == 0 and can_short:
                position = -1
                min_price = price
                open_price = price
                trades += 1
            elif position == 1 and can_short:
                realize(price, 1, per_number)
                position = -1
                min_price = price
                open_price = price
                trades += 1

        if position == 1 and price <= open_price * 0.9:
            realize(price, 1, per_number)
            position = 0
            can_long = False
            trades += 1

        if position == -1 and price >= min_price * 1.03:
            realize(price, -1, per_number)
            position = 0
            can_short = False
            trades += 1

        equity = mark_equity(price)
        if equity < min_equity:
            min_equity = equity
        if equity > peak:
            peak = equity
        drawdown = peak - equity
        if drawdown > max_drawdown:
            max_drawdown = drawdown

    final_equity = mark_equity(float(data['close'].iloc[-1]))
    return {
        'bars': len(data),
        'trades': trades,
        'final_equity': final_equity,
        'min_equity': min_equity,
        'max_drawdown': max_drawdown,
    }


def main():
    parser = argparse.ArgumentParser(description='OKX RSI 策略离线回测')
    parser.add_argument('--csv', default=DEFAULT_CSV, help='K 线 CSV 路径')
    parser.add_argument('--download', action='store_true', help='用 OKX 公开行情下载 K 线')
    parser.add_argument('--pages', type=int, default=3, help='下载分页数，每页最多 100 根')
    parser.add_argument('--contracts', type=float, default=BACKTEST_CONTRACTS, help='每次下单张数')
    args = parser.parse_args()

    swap_name, _ = load_public_config()
    per_number = args.contracts
    if args.download:
        data = download_history(swap_name, '30m', args.pages)
    else:
        if not os.path.isfile(args.csv):
            raise SystemExit(f'找不到 CSV: {args.csv}')
        data = load_csv(args.csv)

    data = add_rsi(data)
    result = run_backtest(data, per_number)
    print(f'标的: {swap_name}')
    print(f'每次张数: {per_number}')
    print(f'K线根数: {result["bars"]}')
    print(f'成交笔数: {result["trades"]}')
    print(f'期末权益: {result["final_equity"]:.4f}')
    print(f'最低权益: {result["min_equity"]:.4f}')
    print(f'最大回撤: {result["max_drawdown"]:.4f}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
