#!/bin/bash
set -e

# 配置项（需与部署脚本的BIN_DEST一致）
BIN_PATH="./mk48-plus-bin"

# 检查bin文件是否存在
if [ ! -f "${BIN_PATH}" ]; then
    echo "错误：bin文件不存在，请先执行部署脚本 deploy.sh"
    exit 1
fi

# 检查bin文件是否可执行
if [ ! -x "${BIN_PATH}" ]; then
    echo "警告：bin文件不可执行，正在赋予执行权限..."
    chmod +x "${BIN_PATH}"
fi

# 运行bin文件（支持传递参数，例如：./start.sh --port 8080）
echo "===== 启动mk48-plus ====="
exec "${BIN_PATH}" "$@"
