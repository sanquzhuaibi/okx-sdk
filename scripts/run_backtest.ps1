# 在 Windows 上跑通 Docker 回测。由 run_backtest.bat 调用。
# 本文件必须保存为 UTF-8 BOM。

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

function Invoke-NativeBacktest {
    $csv = Join-Path $Root "data\BTCUSDT_data_30min.csv"
    if (-not (Test-Path -LiteralPath $csv)) {
        throw "缺少 data\BTCUSDT_data_30min.csv。请确认仓库完整克隆，该文件应已在 git 中。"
    }

    $images = @(
        "docker.m.daocloud.io/library/python:3.10-slim",
        "docker.1ms.run/library/python:3.10-slim",
        "public.ecr.aws/docker/library/python:3.10-slim",
        "python:3.10-slim"
    )
    $picked = $null
    foreach ($img in $images) {
        Write-Host "尝试拉取 $img"
        & docker pull $img
        if ($LASTEXITCODE -eq 0) {
            $picked = $img
            break
        }
        Write-Host "拉取失败，尝试下一个镜像源"
    }
    if (-not $picked) {
        throw "基础镜像全部拉取失败。请检查网络或配置 Docker registry mirror 后重试。"
    }

    Write-Host "使用基础镜像: $picked"
    & docker build -t okx-sdk:backtest --build-arg "PYTHON_IMAGE=$picked" $Root
    if ($LASTEXITCODE -ne 0) { throw "镜像构建失败" }

    $output = & docker run --rm okx-sdk:backtest python tests/rsi_backtest.py
    if ($LASTEXITCODE -ne 0) { throw "回测容器退出码 $LASTEXITCODE" }
    $text = ($output | Out-String)
    Write-Host $text

    $expected = @(
        "每次张数: 5.76",
        "K线根数: 83086",
        "成交笔数: 590",
        "期末权益: 16759.5685",
        "最低权益: 7649.6107",
        "最大回撤: 2998.1059"
    )
    foreach ($line in $expected) {
        if ($text -notlike "*$line*") {
            throw "回测输出缺少: $line"
        }
    }
    Write-Host "回测通过"
}

$dockerCmd = Get-Command docker -ErrorAction SilentlyContinue
$nativeOk = $false
if ($dockerCmd) {
    & docker info *> $null
    $nativeOk = $LASTEXITCODE -eq 0
}

if ($nativeOk) {
    Invoke-NativeBacktest
    exit 0
}

if (Get-Command wsl -ErrorAction SilentlyContinue) {
    Write-Host "Windows 上未检测到可用的 docker，改用 WSL 中的 Docker。"
    wsl -u root -e sh -c "if ! docker info >/dev/null 2>&1; then service docker start; sleep 2; fi"
    $wslRoot = (wsl -e wslpath -a $Root).Trim()
    wsl -e bash -lc "cd '$wslRoot' && bash scripts/run_backtest.sh"
    exit $LASTEXITCODE
}

Write-Host "未找到 Docker。请安装 Docker Desktop，或在 WSL 中安装 Docker Engine 后重新运行 scripts\run_backtest.bat"
exit 1
