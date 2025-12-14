#!/bin/bash
set -e  # 遇到错误立即退出

# 配置项（可根据实际情况修改）
REPO_OWNER="turkey1024"
REPO_NAME="mk48-plus"
ARTIFACTS_DIR="./mk48_artifacts"  # 临时解压目录
BIN_DEST="./mk48-plus-bin"        # 最终bin文件存放路径

# 第一步：安装依赖（Render环境可能已预装，此处做兼容）
echo "===== 安装依赖 ====="
if [ "$(uname -s)" = "Linux" ]; then
    # Debian/Ubuntu系（Render使用的是Ubuntu）
    apt update && apt install -y curl jq unzip tar
elif [ "$(uname -s)" = "Darwin" ]; then
    # macOS（本地测试用）
    brew install curl jq unzip tar
fi

# 第二步：创建临时目录
echo "===== 创建临时目录 ====="
rm -rf "${ARTIFACTS_DIR}"
mkdir -p "${ARTIFACTS_DIR}"

# 第三步：获取最新Workflow的Run ID（通过GitHub API）
echo "===== 获取最新Workflow Run ID ====="
# 获取仓库最新的Workflow Runs（只取成功的、最新的一个）
RUN_ID=$(curl -s "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs?per_page=1&status=success" \
    | jq -r '.workflow_runs[0].id')

if [ -z "${RUN_ID}" ] || [ "${RUN_ID}" = "null" ]; then
    echo "错误：未找到最新的成功Workflow Run"
    exit 1
fi
echo "最新Workflow Run ID: ${RUN_ID}"

# 第四步：获取该Run的Artifacts列表，提取第一个Artifacts的ID和名称
echo "===== 获取Artifacts信息 ====="
ARTIFACTS_INFO=$(curl -s "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/runs/${RUN_ID}/artifacts")
ARTIFACT_ID=$(echo "${ARTIFACTS_INFO}" | jq -r '.artifacts[0].id')
ARTIFACT_NAME=$(echo "${ARTIFACTS_INFO}" | jq -r '.artifacts[0].name')

if [ -z "${ARTIFACT_ID}" ] || [ "${ARTIFACT_ID}" = "null" ]; then
    echo "错误：未找到该Workflow的Artifacts"
    exit 1
fi
echo "最新Artifacts ID: ${ARTIFACT_ID}，名称: ${ARTIFACT_NAME}"

# 第五步：下载Artifacts压缩包
echo "===== 下载Artifacts ====="
ARTIFACT_ZIP="${ARTIFACTS_DIR}/${ARTIFACT_NAME}.zip"
curl -s -L \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/actions/artifacts/${ARTIFACT_ID}/zip" \
    -o "${ARTIFACT_ZIP}"

if [ ! -f "${ARTIFACT_ZIP}" ]; then
    echo "错误：Artifacts压缩包下载失败"
    exit 1
fi

# 第六步：解压zip包
echo "===== 解压ZIP包 ====="
unzip -q "${ARTIFACT_ZIP}" -d "${ARTIFACTS_DIR}"

# 第七步：查找并解压tar.gz包
echo "===== 解压tar.gz包 ====="
TAR_GZ_FILE=$(find "${ARTIFACTS_DIR}" -name "*.tar.gz" | head -n 1)
if [ -z "${TAR_GZ_FILE}" ]; then
    echo "错误：未找到tar.gz文件"
    exit 1
fi
tar -zxf "${TAR_GZ_FILE}" -C "${ARTIFACTS_DIR}"

# 第八步：查找bin文件并移动到目标路径
echo "===== 提取bin文件 ====="
BIN_FILE=$(find "${ARTIFACTS_DIR}" -type f -executable -name "*.bin" -o -name "mk48-plus" | head -n 1)
if [ -z "${BIN_FILE}" ]; then
    echo "错误：未找到可执行的bin文件"
    exit 1
fi

# 移动bin文件到指定位置
mv "${BIN_FILE}" "${BIN_DEST}"
chmod +x "${BIN_DEST}"

# 清理临时目录
rm -rf "${ARTIFACTS_DIR}"

echo "===== 部署完成 ====="
echo "bin文件路径：$(realpath "${BIN_DEST}")"
