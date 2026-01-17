#!/bin/bash

# 验证测试脚本
# 测试 Elasticdump Easy 的核心功能

set -e

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# 测试计数
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# 打印函数
print_test() {
    echo -e "\n${BOLD}${BLUE}━━━ 测试 $((TOTAL_TESTS + 1)): $1 ━━━${NC}"
}

pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# 测试 1: 版本命令
print_test "版本命令"
if ./bin/elasticdump-easy --version | grep -q "Elasticdump Easy v"; then
    pass "版本命令正常工作"
else
    fail "版本命令失败"
fi

# 测试 2: 帮助命令
print_test "帮助命令"
if ./bin/elasticdump-easy --help | grep -q "用法:"; then
    pass "帮助命令正常工作"
else
    fail "帮助命令失败"
fi

# 测试 3: 未知命令错误处理
print_test "未知命令错误处理"
if ./bin/elasticdump-easy unknown-command 2>&1 | grep -q "未知命令"; then
    pass "未知命令错误处理正常"
else
    fail "未知命令错误处理失败"
fi

# 测试 4: test 命令（无效连接）
print_test "test 命令（无效连接）"
if ./bin/elasticdump-easy test --from http://invalid-host:9200 2>&1 | grep -q "连接失败"; then
    pass "test 命令正确检测到连接失败"
else
    fail "test 命令未能检测连接失败"
fi

# 测试 5: list 命令
print_test "list 命令"
if ./bin/elasticdump-easy list 2>&1 | grep -q "任务列表"; then
    pass "list 命令正常工作"
else
    fail "list 命令失败"
fi

# 测试 6: dump 命令参数验证（缺少索引名）
print_test "dump 命令参数验证"
if ./bin/elasticdump-easy dump 2>&1 | grep -q "请指定索引名称"; then
    pass "dump 命令正确验证参数"
else
    fail "dump 命令参数验证失败"
fi

# 测试 7: 文件结构
print_test "文件结构完整性"
files_ok=true
for file in bin/elasticdump-easy lib/utils.sh lib/config.sh lib/cli.sh lib/dump.sh lib/progress.sh lib/error.sh install.sh README.md LICENSE; do
    if [ ! -f "$file" ]; then
        echo "  缺少文件: $file"
        files_ok=false
    fi
done

if [ "$files_ok" = true ]; then
    pass "所有必需文件都存在"
else
    fail "缺少必需文件"
fi

# 测试 8: 脚本可执行权限
print_test "脚本可执行权限"
if [ -x "bin/elasticdump-easy" ] && [ -x "install.sh" ]; then
    pass "脚本具有可执行权限"
else
    fail "脚本缺少可执行权限"
fi

# 测试 9: README 核心痛点覆盖
print_test "README 核心痛点覆盖"
readme_ok=true
pain_points=(
    "Session 过期"
    "配置管理"
    "参数优化"
    "分页方式"
    "大索引"
    "进度反馈"
)

for point in "${pain_points[@]}"; do
    if ! grep -q "$point" README.md; then
        echo "  README 未覆盖: $point"
        readme_ok=false
    fi
done

if [ "$readme_ok" = true ]; then
    pass "README 覆盖所有核心痛点"
else
    fail "README 未完全覆盖核心痛点"
fi

# 测试 10: 模块加载
print_test "模块加载测试"
if bash -c "
    SCRIPT_DIR='$(pwd)'
    source lib/utils.sh 2>/dev/null && \
    source lib/config.sh 2>/dev/null && \
    source lib/cli.sh 2>/dev/null && \
    source lib/dump.sh 2>/dev/null && \
    source lib/progress.sh 2>/dev/null && \
    source lib/error.sh 2>/dev/null
"; then
    pass "所有模块可以正常加载"
else
    fail "模块加载失败"
fi

# 测试总结
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}测试总结${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "总测试数: $TOTAL_TESTS"
echo -e "${GREEN}通过: $PASSED_TESTS${NC}"
echo -e "${RED}失败: $FAILED_TESTS${NC}"
echo ""

if [ $FAILED_TESTS -eq 0 ]; then
    echo -e "${GREEN}${BOLD}✓ 所有测试通过！${NC}"
    exit 0
else
    echo -e "${RED}${BOLD}✗ 有测试失败${NC}"
    exit 1
fi
