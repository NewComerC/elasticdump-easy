#!/bin/bash

# Elasticdump Easy 安装脚本
# 一键安装所有依赖

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# 打印函数
print_header() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_info() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

print_step() {
    echo -e "\n${BOLD}▶ $1${NC}"
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        OS="unknown"
        OS_VERSION="unknown"
    fi
    
    OS=$(echo "$OS" | tr '[:upper:]' '[:lower:]')
    print_info "操作系统: $OS $OS_VERSION"
}

# 检查 root 权限
check_sudo() {
    if [ "$EUID" -ne 0 ]; then
        if command_exists sudo; then
            USE_SUDO="sudo"
            print_warn "需要 sudo 权限来安装依赖"
        else
            print_error "需要 root 权限或 sudo 命令"
            exit 1
        fi
    else
        USE_SUDO=""
    fi
}

# 安装 Node.js (Ubuntu/Debian)
install_nodejs_debian() {
    print_step "安装 Node.js 和 npm"
    
    if command_exists node && command_exists npm; then
        print_info "Node.js 已安装: $(node --version)"
        print_info "npm 已安装: $(npm --version)"
        return 0
    fi
    
    print_info "更新软件包列表..."
    $USE_SUDO apt-get update -qq
    
    print_info "安装依赖..."
    $USE_SUDO apt-get install -y -qq curl ca-certificates gnupg
    
    print_info "添加 NodeSource 仓库..."
    if [ ! -f /etc/apt/sources.list.d/nodesource.list ]; then
        curl -fsSL https://deb.nodesource.com/setup_lts.x | $USE_SUDO bash - >/dev/null 2>&1
    fi
    
    print_info "安装 Node.js..."
    $USE_SUDO apt-get install -y -qq nodejs
    
    if command_exists node && command_exists npm; then
        print_info "✓ Node.js 安装成功: $(node --version)"
        print_info "✓ npm 安装成功: $(npm --version)"
        return 0
    else
        print_error "Node.js 安装失败"
        return 1
    fi
}

# 安装 Node.js (通用方法)
install_nodejs_generic() {
    print_step "安装 Node.js 和 npm"
    
    if command_exists node && command_exists npm; then
        print_info "Node.js 已安装: $(node --version)"
        print_info "npm 已安装: $(npm --version)"
        return 0
    fi
    
    print_warn "检测到非 Debian/Ubuntu 系统"
    print_info "请手动安装 Node.js 和 npm"
    print_info "访问: https://nodejs.org/"
    return 1
}

# 安装 elasticdump
install_elasticdump() {
    print_step "安装 elasticdump"
    
    if command_exists elasticdump; then
        print_info "elasticdump 已安装"
        return 0
    fi
    
    if ! command_exists npm; then
        print_error "npm 未安装，无法安装 elasticdump"
        return 1
    fi
    
    print_info "使用 npm 全局安装 elasticdump..."
    
    if $USE_SUDO npm install -g elasticdump >/dev/null 2>&1; then
        print_info "✓ elasticdump 安装成功"
        return 0
    else
        print_error "elasticdump 安装失败"
        print_info "请尝试手动安装: sudo npm install -g elasticdump"
        return 1
    fi
}

# 安装可选依赖
install_optional_deps() {
    print_step "安装可选依赖"
    
    local missing_deps=()
    
    # 检查 jq
    if ! command_exists jq; then
        missing_deps+=("jq")
    else
        print_info "✓ jq 已安装"
    fi
    
    # 检查 python3
    if ! command_exists python3; then
        missing_deps+=("python3")
    else
        print_info "✓ python3 已安装"
    fi
    
    # 检查 curl
    if ! command_exists curl; then
        missing_deps+=("curl")
    else
        print_info "✓ curl 已安装"
    fi
    
    # 安装缺失的依赖
    if [ ${#missing_deps[@]} -gt 0 ]; then
        case "$OS" in
            ubuntu|debian)
                print_info "安装: ${missing_deps[*]}"
                $USE_SUDO apt-get install -y -qq "${missing_deps[@]}"
                ;;
            centos|rhel|fedora)
                print_info "安装: ${missing_deps[*]}"
                $USE_SUDO yum install -y "${missing_deps[@]}" >/dev/null 2>&1
                ;;
            *)
                print_warn "请手动安装: ${missing_deps[*]}"
                ;;
        esac
    fi
}

# 配置全局命令
setup_global_command() {
    print_step "配置全局命令"
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local bin_path="${script_dir}/bin/elasticdump-easy"
    local target_path="/usr/local/bin/elasticdump-easy"
    
    if [ -f "$target_path" ]; then
        print_info "全局命令已配置"
        return 0
    fi
    
    if [ -f "$bin_path" ]; then
        print_info "创建符号链接..."
        $USE_SUDO ln -sf "$bin_path" "$target_path"
        print_info "✓ 全局命令已配置: elasticdump-easy"
    else
        print_warn "未找到主脚本: $bin_path"
        return 1
    fi
}

# 验证安装
verify_installation() {
    print_step "验证安装"
    
    local all_ok=true
    
    # 检查 Node.js
    if command_exists node; then
        print_info "✓ Node.js: $(node --version)"
    else
        print_error "✗ Node.js 未安装"
        all_ok=false
    fi
    
    # 检查 npm
    if command_exists npm; then
        print_info "✓ npm: $(npm --version)"
    else
        print_error "✗ npm 未安装"
        all_ok=false
    fi
    
    # 检查 elasticdump
    if command_exists elasticdump; then
        print_info "✓ elasticdump: 已安装"
    else
        print_error "✗ elasticdump 未安装"
        all_ok=false
    fi
    
    # 检查主命令
    if command_exists elasticdump-easy; then
        print_info "✓ elasticdump-easy: 已配置"
    else
        print_warn "⚠ elasticdump-easy: 未配置为全局命令"
        print_info "  可以使用: ./bin/elasticdump-easy"
    fi
    
    if [ "$all_ok" = true ]; then
        return 0
    else
        return 1
    fi
}

# 显示完成信息
show_completion() {
    echo ""
    echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}${BOLD}  ✓ 安装完成！${NC}"
    echo -e "${GREEN}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "快速开始:"
    echo ""
    echo "  1. 查看帮助"
    echo "     elasticdump-easy --help"
    echo ""
    echo "  2. 测试连接"
    echo "     elasticdump-easy test --from http://localhost:9200"
    echo ""
    echo "  3. 开始导出"
    echo "     elasticdump-easy dump my_index"
    echo ""
    echo "  4. 配置向导"
    echo "     elasticdump-easy init"
    echo ""
    echo "更多信息:"
    echo "  GitHub: https://github.com/NewComerC/elasticdump-easy"
    echo "  文档:   https://github.com/NewComerC/elasticdump-easy#readme"
    echo ""
}

# 主函数
main() {
    print_header "Elasticdump Easy 安装程序"
    
    # 检测系统
    detect_os
    check_sudo
    
    # 安装 Node.js
    case "$OS" in
        ubuntu|debian)
            install_nodejs_debian || exit 1
            ;;
        *)
            install_nodejs_generic || {
                print_error "请手动安装 Node.js 后重试"
                exit 1
            }
            ;;
    esac
    
    # 安装 elasticdump
    install_elasticdump || exit 1
    
    # 安装可选依赖
    install_optional_deps
    
    # 配置全局命令
    setup_global_command
    
    # 验证安装
    if verify_installation; then
        show_completion
        exit 0
    else
        echo ""
        print_error "安装未完全成功，请检查上述错误"
        exit 1
    fi
}

# 运行主函数
main "$@"
