# 由 scripts/run_backtest.sh 传入第一个能拉取成功的镜像。
# 默认用 DaoCloud：本机配置的 Docker Hub 镜像站会返回 403。
ARG PYTHON_IMAGE=docker.m.daocloud.io/library/python:3.10-slim
FROM ${PYTHON_IMAGE}

WORKDIR /app

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# 先试清华 apt 源，失败再退回镜像自带源。
RUN set -eux; \
    src=/etc/apt/sources.list.d/debian.sources; \
    if [ -f "$src" ]; then \
      cp "$src" /tmp/debian.sources.bak; \
      sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g; s/security.debian.org/mirrors.tuna.tsinghua.edu.cn/g' "$src"; \
      if ! apt-get update; then \
        cp /tmp/debian.sources.bak "$src"; \
        apt-get update; \
      fi; \
    else \
      cp /etc/apt/sources.list /tmp/sources.list.bak; \
      sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g; s/security.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list; \
      if ! apt-get update; then \
        cp /tmp/sources.list.bak /etc/apt/sources.list; \
        apt-get update; \
      fi; \
    fi; \
    apt-get install -y --no-install-recommends gcc g++ libssl-dev; \
    rm -rf /var/lib/apt/lists/*

# 回测只需要 pandas 和本仓库。不安装 requirements.txt
# （其中有 win32-setctime 等 Windows 包，Linux 镜像装不上）。
COPY . .
RUN (pip install --no-cache-dir -i https://pypi.tuna.tsinghua.edu.cn/simple pandas \
      || pip install --no-cache-dir pandas) \
    && (pip install --no-cache-dir -i https://pypi.tuna.tsinghua.edu.cn/simple -e . \
      || pip install --no-cache-dir -e .)

RUN mkdir -p /app/logs \
    && test -f /app/data/BTCUSDT_data_30min.csv

# 镜像默认执行已在容器里跑通的离线回测。实盘需另行指定命令。
CMD ["python", "tests/rsi_backtest.py"]
