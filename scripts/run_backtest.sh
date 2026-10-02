#!/usr/bin/env bash
# 构建镜像并跑通 RSI 离线回测。K 线随仓库提交，构建时打进镜像。
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v docker >/dev/null 2>&1; then
  echo "未找到 docker。请先安装 Docker Engine 或 Docker Desktop，然后重新运行本脚本。"
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  if [ "$(id -u)" -eq 0 ] && command -v service >/dev/null 2>&1; then
    service docker start
    sleep 2
  fi
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker 已安装但服务未启动。Linux 可执行: sudo service docker start"
  exit 1
fi

if [ ! -f data/BTCUSDT_data_30min.csv ]; then
  echo "缺少 data/BTCUSDT_data_30min.csv。请确认仓库完整克隆，该文件应已在 git 中。"
  exit 1
fi

images=(
  "docker.m.daocloud.io/library/python:3.10-slim"
  "docker.1ms.run/library/python:3.10-slim"
  "public.ecr.aws/docker/library/python:3.10-slim"
  "python:3.10-slim"
)

picked=""
for img in "${images[@]}"; do
  echo "尝试拉取 ${img}"
  if docker pull "$img"; then
    picked="$img"
    break
  fi
  echo "拉取失败，尝试下一个镜像源"
done

if [ -z "$picked" ]; then
  echo "基础镜像全部拉取失败。请检查网络或配置 Docker registry mirror 后重试。"
  exit 1
fi

echo "使用基础镜像: ${picked}"
docker build -t okx-sdk:backtest --build-arg "PYTHON_IMAGE=${picked}" .

output="$(docker run --rm okx-sdk:backtest python tests/rsi_backtest.py)"
printf '%s\n' "$output"

need() {
  if ! printf '%s\n' "$output" | grep -F -q "$1"; then
    echo "回测输出缺少: $1"
    exit 1
  fi
}

need "每次张数: 5.76"
need "K线根数: 83086"
need "成交笔数: 590"
need "期末权益: 16759.5685"
need "最低权益: 7649.6107"
need "最大回撤: 2998.1059"
echo "回测通过"
