#!/bin/bash
set -euo pipefail  # 严格的错误处理

# ===================== 配置项 =====================
REPO_OWNER="turkey1024"
REPO_NAME="mk48-plus"
ARTIFACTS_DIR="./mk48_artifacts"  # 临时解压目录
BIN_DEST="./mk48-plus-bin"        # 最终bin文件路径
# ==================================================

# 第一步：检查必要依赖是否存在
echo "===== 检查依赖 ====="
required_tools=("curl" "jq" "unzip" "tar" "gh")
for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        echo "错误：未找到 $tool，Render 环境应预装，若缺失请联系支持"
        exit 1
    fi
done

# 第二步：配置 GitHub CLI（可选，用于避免 API 速率限制）
# 若 Render 中配置了 GITHUB_TOKEN 环境变量，gh 会自动使用
if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo "===== 配置 GitHub CLI 鉴权 ====="
    echo "$GITHUB_TOKEN" | gh auth login --with-token
fi

# 第三步：创建并清理临时目录
echo "===== 初始化临时目录 ====="
rm -rf "${ARTIFACTS_DIR}"
mkdir -p "${ARTIFACTS_DIR}"

# 第四步：获取最新成功的 Workflow Run ID
echo "===== 获取最新Workflow Run ID ====="
RUN_ID=$(gh api "repos/${REPO_OWNER}/${REPO_NAME}/actions/runs?per_page=1&status=success" \
    | jq -r '.workflow_runs[0].id')

if [ -z "${RUN_ID}" ] || [ "${RUN_ID}" = "null" ]; then
    echo "错误：未找到最新的成功Workflow Run"
    exit 1
fi
echo "最新Workflow Run ID: ${RUN_ID}"

# 第五步：获取该 Run 的第一个 Artifacts 名称
echo "===== 获取Artifacts信息 ====="
ARTIFACT_NAME=$(gh api "repos/${REPO_OWNER}/${REPO_NAME}/actions/runs/${RUN_ID}/artifacts" \
    | jq -r '.artifacts[0].name')

if [ -z "${ARTIFACT_NAME}" ] || [ "${ARTIFACT_NAME}" = "null" ]; then
    echo "错误：未找到该Workflow的Artifacts"
    exit 1
fi
echo "最新Artifacts名称: ${ARTIFACT_NAME}"

# 第六步：使用 gh 下载 Artifacts（关键：避免 ZIP 损坏）
echo "===== 下载Artifacts ====="
gh run download "${RUN_ID}" --name "${ARTIFACT_NAME}" --dir "${ARTIFACTS_DIR}"

# 检查下载的文件是否存在
if [ -z "$(ls -A "${ARTIFACTS_DIR}")" ]; then
    echo "错误：Artifacts 下载为空"
    exit 1
fi

# 第七步：解压 ZIP 包（若下载的是 ZIP 包，否则跳过）
echo "===== 解压文件 ====="
ZIP_FILE=$(find "${ARTIFACTS_DIR}" -name "*.zip" | head -n 1)
if [ -n "${ZIP_FILE}" ]; then
    unzip -q "${ZIP_FILE}" -d "${ARTIFACTS_DIR}"
    rm -f "${ZIP_FILE}"  # 删除解压后的 ZIP 包
fi

# 第八步：解压 tar.gz 包
TAR_GZ_FILE=$(find "${ARTIFACTS_DIR}" -name "*.tar.gz" | head -n 1)
if [ -z "${TAR_GZ_FILE}" ]; then
    echo "警告：未找到tar.gz文件，尝试查找其他压缩包"
    # 可选：支持 tar.xz/tar.bz2 等
    TAR_GZ_FILE=$(find "${ARTIFACTS_DIR}" -name "*.tar.xz" -o -name "*.tar.bz2" | head -n 1)
    if [ -n "${TAR_GZ_FILE}" ]; then
        tar -xf "${TAR_GZ_FILE}" -C "${ARTIFACTS_DIR}"
    else
        echo "错误：未找到任何压缩包"
        exit 1
    fi
else
    tar -zxf "${TAR_GZ_FILE}" -C "${ARTIFACTS_DIR}"
fi

# 第九步：查找并提取 bin 文件
echo "===== 提取可执行文件 ====="
# 查找所有可执行文件（优先 mk48-plus 相关，或 .bin 后缀）
BIN_FILE=$(find "${ARTIFACTS_DIR}" -type f -executable \
    \( -name "mk48-plus" -o -name "*.bin" -o -name "mk48" \) | head -n 1)

if [ -z "${BIN_FILE}" ]; then
    echo "警告：未找到指定的可执行文件，尝试查找所有可执行文件"
    # 兜底：取第一个可执行文件
    BIN_FILE=$(find "${ARTIFACTS_DIR}" -type f -executable | head -n 1)
    if [ -z "${BIN_FILE}" ]; then
        echo "错误：未找到任何可执行文件"
        exit 1
    fi
fi

# 移动并赋予执行权限
mv "${BIN_FILE}" "${BIN_DEST}"
chmod +x "${BIN_DEST}"

# 清理临时目录
rm -rf "${ARTIFACTS_DIR}"

echo "===== 部署完成 ====="
echo "可执行文件路径：$(realpath "${BIN_DEST}")"
