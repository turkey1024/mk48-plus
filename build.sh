#!/bin/bash
set -euo pipefail  # 严格的错误处理，防止未定义变量和管道失败

# ===================== 配置项 =====================
REPO_OWNER="turkey1024"
REPO_NAME="mk48-plus"
ARTIFACTS_DIR="./mk48_artifacts"  # 临时解压目录
BIN_DEST="./mk48-plus-bin"        # 最终bin文件路径
# ==================================================

# 第一步：检查必要依赖（仅检查 Render 预装的工具，不安装）
echo "===== 检查依赖 ====="
required_tools=("curl" "jq" "unzip" "tar")
for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        echo "错误：未找到依赖工具 $tool，请在 Render 环境中确认该工具是否存在"
        exit 1
    fi
done

# 检查 GITHUB_TOKEN 是否配置（非必需，但建议配置以避免 API 速率限制）
if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "警告：未配置 GITHUB_TOKEN 环境变量，可能触发 GitHub API 速率限制（每小时60次）"
    sleep 3
fi

# 第二步：创建并清理临时目录
echo "===== 初始化临时目录 ====="
rm -rf "${ARTIFACTS_DIR}"
mkdir -p "${ARTIFACTS_DIR}"

# 第三步：获取最新成功的 Workflow Run ID（通过 GitHub API）
echo "===== 获取最新Workflow Run ID ====="
API_HEADERS=(
    -H "Accept: application/vnd.github.v3+json"
    -H "X-GitHub-Api-Version: 2022-11-28"
)
# 若配置了 GITHUB_TOKEN，添加鉴权头
if [ -n "${GITHUB_TOKEN:-}" ]; then
    API_HEADERS+=(-H "Authorization: token ${GITHUB_TOKEN}")
fi

# 调用 API 获取最新成功的 Run ID
RUN_ID=$(curl -s "${API_HEADERS[@]}" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs?per_page=1&status=success" \
    | jq -r '.workflow_runs[0].id')

# 验证 Run ID 是否有效
if [ -z "${RUN_ID}" ] || [ "${RUN_ID}" = "null" ]; then
    echo "错误：未找到最新的成功Workflow Run，可能原因："
    echo "1. 仓库无成功的 Workflow Run"
    echo "2. GitHub API 速率限制（建议配置 GITHUB_TOKEN）"
    echo "3. 仓库权限问题（GITHUB_TOKEN 需有 repo 和 actions 权限）"
    exit 1
fi
echo "最新Workflow Run ID: ${RUN_ID}"

# 第四步：获取该 Run 的 Artifacts 信息（ID + 名称）
echo "===== 获取Artifacts信息 ====="
ARTIFACTS_RESPONSE=$(curl -s "${API_HEADERS[@]}" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs/${RUN_ID}/artifacts")

ARTIFACT_ID=$(echo "${ARTIFACTS_RESPONSE}" | jq -r '.artifacts[0].id')
ARTIFACT_NAME=$(echo "${ARTIFACTS_RESPONSE}" | jq -r '.artifacts[0].name')

# 验证 Artifacts 是否存在
if [ -z "${ARTIFACT_ID}" ] || [ "${ARTIFACT_ID}" = "null" ]; then
    echo "错误：未找到该Workflow Run的Artifacts"
    exit 1
fi
echo "最新Artifacts ID: ${ARTIFACT_ID}，名称: ${ARTIFACT_NAME}"

# 第五步：下载 Artifacts 压缩包（关键：修复请求头避免 ZIP 损坏）
echo "===== 下载Artifacts ====="
ARTIFACT_ZIP="${ARTIFACTS_DIR}/${ARTIFACT_NAME}.zip"

# 下载 Artifacts：使用 application/octet-stream 接受二进制流，避免 API 返回 JSON 错误
curl -s -L "${API_HEADERS[@]}" \
    -H "Accept: application/octet-stream" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/artifacts/${ARTIFACT_ID}/zip" \
    -o "${ARTIFACT_ZIP}"

# 验证下载的文件是否为有效 ZIP 包（通过文件魔数检测）
if [ ! -f "${ARTIFACT_ZIP}" ] || [ $(stat -c%s "${ARTIFACT_ZIP}") -lt 100 ]; then
    echo "错误：Artifacts 下载失败或文件过小，可能是 API 返回了错误信息（如权限不足）"
    # 打印下载的文件内容，便于调试
    echo "下载的文件内容："
    cat "${ARTIFACT_ZIP}"
    exit 1
fi

# 检测文件魔数是否为 ZIP 格式（ZIP 魔数：50 4B 03 04 或 50 4B 05 06 或 50 4B 07 08）
ZIP_MAGIC=$(head -c 4 "${ARTIFACT_ZIP}" | xxd -p)
if [[ ! "${ZIP_MAGIC}" =~ ^504b0304|504b0506|504b0708$ ]]; then
    echo "警告：文件魔数不是 ZIP 格式，尝试直接作为压缩包解压"
    # 重命名为 tar.gz 尝试解压（应对 Artifacts 实际为 tar.gz 的情况）
    mv "${ARTIFACT_ZIP}" "${ARTIFACTS_DIR}/${ARTIFACT_NAME}.tar.gz"
    TAR_GZ_FILE="${ARTIFACTS_DIR}/${ARTIFACT_NAME}.tar.gz"
else
    echo "验证通过：下载的文件是有效 ZIP 包"
fi

# 第六步：解压文件（兼容 ZIP 和 tar.gz 两种格式）
echo "===== 解压文件 ====="
# 优先处理 ZIP 包
if [ -f "${ARTIFACT_ZIP}" ]; then
    unzip -q "${ARTIFACT_ZIP}" -d "${ARTIFACTS_DIR}"
    rm -f "${ARTIFACT_ZIP}"  # 删除解压后的 ZIP 包
fi

# 查找并解压 tar.gz/tar.xz 等压缩包
COMPRESS_FILE=$(find "${ARTIFACTS_DIR}" -name "*.tar.gz" -o -name "*.tar.xz" -o -name "*.tar.bz2" | head -n 1)
if [ -n "${COMPRESS_FILE}" ]; then
    case "${COMPRESS_FILE}" in
        *.tar.gz) tar -zxf "${COMPRESS_FILE}" -C "${ARTIFACTS_DIR}" ;;
        *.tar.xz) tar -xf "${COMPRESS_FILE}" -C "${ARTIFACTS_DIR}" ;;
        *.tar.bz2) tar -jxf "${COMPRESS_FILE}" -C "${ARTIFACTS_DIR}" ;;
    esac
    rm -f "${COMPRESS_FILE}"  # 删除解压后的压缩包
elif [ -f "${TAR_GZ_FILE:-}" ]; then
    # 处理之前魔数不对的情况
    tar -zxf "${TAR_GZ_FILE}" -C "${ARTIFACTS_DIR}"
    rm -f "${TAR_GZ_FILE}"
fi

# 第七步：查找并提取可执行文件
echo "===== 提取可执行文件 ====="
# 查找优先级：mk48-plus > *.bin > mk48 > 所有可执行文件
BIN_FILE=$(find "${ARTIFACTS_DIR}" -type f -executable \
    \( -name "mk48-plus" -o -name "*.bin" -o -name "mk48" \) | head -n 1)

# 兜底：取第一个可执行文件
if [ -z "${BIN_FILE}" ]; then
    BIN_FILE=$(find "${ARTIFACTS_DIR}" -type f -executable | head -n 1)
fi

# 验证可执行文件是否存在
if [ -z "${BIN_FILE}" ]; then
    echo "错误：未找到任何可执行文件"
    # 列出目录内容，便于调试
    echo "Artifacts 目录内容："
    ls -la "${ARTIFACTS_DIR}"
    exit 1
fi

# 移动并赋予执行权限
mv "${BIN_FILE}" "${BIN_DEST}"
chmod +x "${BIN_DEST}"

# 清理临时目录
rm -rf "${ARTIFACTS_DIR}"

echo "===== 部署完成 ====="
echo "可执行文件路径：$(realpath "${BIN_DEST}")"
