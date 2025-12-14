#!/bin/bash
set -euo pipefail  # 严格的错误处理

# ===================== 配置项 =====================
TAR_FILE="mk48-linux-x64.tar.gz"  # 仓库根目录的压缩包名称
ARTIFACTS_DIR="./mk48_artifacts"  # 临时解压目录
BIN_DEST="./mk48-plus-bin"        # 最终可执行文件路径（软链接到 mk48-server）
# ==================================================

# 第一步：检查必要依赖（Render 已预装）
echo "===== 检查依赖 ====="
required_tools=("tar" "chmod")
for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        echo "错误：未找到依赖工具 $tool，请确认 Render 环境是否预装"
        exit 1
    fi
done

# 第二步：检查压缩包是否存在
echo "===== 检查压缩包 ====="
if [ ! -f "${TAR_FILE}" ]; then
    echo "错误：仓库根目录未找到 ${TAR_FILE} 文件，检查："
    echo "1. Workflow 是否成功将文件推送到仓库根目录"
    echo "2. 文件名称是否与配置项 TAR_FILE 一致"
    # 列出仓库根目录文件，便于调试
    echo "仓库根目录文件列表："
    ls -la
    exit 1
fi
echo "✅ 找到压缩包：${TAR_FILE}"

# 第三步：创建并清理临时目录
echo "===== 初始化临时目录 ====="
rm -rf "${ARTIFACTS_DIR}"
mkdir -p "${ARTIFACTS_DIR}"

# 第四步：解压 tar.gz 包
echo "===== 解压 ${TAR_FILE} ====="
tar -zxf "${TAR_FILE}" -C "${ARTIFACTS_DIR}"

# 第五步：查找可执行文件（mk48-server）
echo "===== 提取可执行文件 ====="
BIN_FILE=$(find "${ARTIFACTS_DIR}" -type f -executable -name "mk48-server" | head -n 1)

# 兜底：若未找到 mk48-server，取第一个可执行文件
if [ -z "${BIN_FILE}" ]; then
    echo "警告：未找到 mk48-server，尝试查找所有可执行文件"
    BIN_FILE=$(find "${ARTIFACTS_DIR}" -type f -executable | head -n 1)
fi

# 验证可执行文件是否存在
if [ -z "${BIN_FILE}" ]; then
    echo "错误：未找到任何可执行文件"
    # 列出解压后的目录内容，便于调试
    echo "解压后的目录内容："
    ls -la "${ARTIFACTS_DIR}"
    exit 1
fi

# 第六步：移动并赋予执行权限
mv "${BIN_FILE}" "${BIN_DEST}"
chmod +x "${BIN_DEST}"

# 清理临时目录
rm -rf "${ARTIFACTS_DIR}"

echo "===== 部署完成 ====="
echo "可执行文件路径：$(realpath "${BIN_DEST}")"
