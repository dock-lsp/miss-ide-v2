#!/bin/bash

# Miss IDE v2 版本更新脚本
# 用法: ./scripts/bump_version.sh [build|patch|minor|major]

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 项目根目录
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# 版本类型默认为 build
VERSION_TYPE="${1:-build}"

# 获取当前版本
CURRENT_VERSION=$(grep "^version:" pubspec.yaml | cut -d':' -f2 | tr -d ' ')
echo -e "${YELLOW}当前版本: $CURRENT_VERSION${NC}"

# 解析版本号
IFS='.' read -ra VERSION_PARTS <<< "$CURRENT_VERSION"
IFS='+' read -ra BUILD_PARTS <<< "${VERSION_PARTS[2]}"

MAJOR="${VERSION_PARTS[0]}"
MINOR="${VERSION_PARTS[1]}"
PATCH="${BUILD_PARTS[0]}"
BUILD="${BUILD_PARTS[1]:-0}"

echo "解析: MAJOR=$MAJOR MINOR=$MINOR PATCH=$PATCH BUILD=$BUILD"

# 根据版本类型递增
case $VERSION_TYPE in
    build)
        NEW_BUILD=$((BUILD + 1))
        NEW_PATCH=$PATCH
        NEW_MINOR=$MINOR
        NEW_MAJOR=$MAJOR
        ;;
    patch)
        NEW_BUILD=1
        NEW_PATCH=$((PATCH + 1))
        NEW_MINOR=$MINOR
        NEW_MAJOR=$MAJOR
        ;;
    minor)
        NEW_BUILD=1
        NEW_PATCH=0
        NEW_MINOR=$((MINOR + 1))
        NEW_MAJOR=$MAJOR
        ;;
    major)
        NEW_BUILD=1
        NEW_PATCH=0
        NEW_MINOR=0
        NEW_MAJOR=$((MAJOR + 1))
        ;;
    *)
        echo -e "${RED}无效的版本类型: $VERSION_TYPE${NC}"
        echo "用法: ./scripts/bump_version.sh [build|patch|minor|major]"
        exit 1
        ;;
esac

# 构建新版本号
NEW_VERSION="${NEW_MAJOR}.${NEW_MINOR}.${NEW_PATCH}+${NEW_BUILD}"
TAG="v${NEW_MAJOR}.${NEW_MINOR}.${NEW_PATCH}"

echo -e "${GREEN}新版本: $NEW_VERSION${NC}"
echo "Tag: $TAG"

# 更新 pubspec.yaml
sed -i "s/^version:.*/version: $NEW_VERSION/" pubspec.yaml

echo -e "${GREEN}✓ pubspec.yaml 已更新${NC}"

# 检查是否有未提交的更改
if git diff --quiet pubspec.yaml; then
    echo -e "${YELLOW}没有需要提交的更改${NC}"
else
    echo -e "${GREEN}版本号已更新，准备提交...${NC}"
    git add pubspec.yaml
    git commit -m "chore: bump version to $NEW_VERSION"
    echo -e "${GREEN}✓ 已提交版本更新${NC}"
fi

echo ""
echo "=========================================="
echo "版本更新完成"
echo "新版本: $NEW_VERSION"
echo "Tag: $TAG"
echo "=========================================="
