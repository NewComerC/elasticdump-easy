#!/bin/bash

# 工具函数模块

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 日志函数
info() {
    echo -e "${GREEN}✓${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1" >&2
}

debug() {
    if [ "${DEBUG_MODE:-false}" = "true" ]; then
        echo -e "${CYAN}[DEBUG]${NC} $1" >&2
    fi
}

section() {
    echo -e "\n${BOLD}${BLUE}▶${NC} ${BOLD}$1${NC}"
}

success() {
    echo -e "\n${GREEN}✓ $1${NC}\n"
}

# 进度条函数
show_progress() {
    local current=$1
    local total=$2
    local width=40
    local percentage=$((current * 100 / total))
    local filled=$((width * current / total))
    local empty=$((width - filled))
    
    printf "\r进度: ["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %3d%% (%'d/%'d)" "$percentage" "$current" "$total"
}

# 格式化时间
format_time() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    printf "%02d:%02d:%02d" "$hours" "$minutes" "$secs"
}

# 格式化大小
format_size() {
    local bytes=$1
    if [ "$bytes" -lt 1024 ]; then
        echo "${bytes}B"
    elif [ "$bytes" -lt 1048576 ]; then
        echo "$((bytes / 1024))KB"
    elif [ "$bytes" -lt 1073741824 ]; then
        echo "$((bytes / 1048576))MB"
    else
        echo "$((bytes / 1073741824))GB"
    fi
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检查文件是否存在
file_exists() {
    [ -f "$1" ]
}

# 检查目录是否存在
dir_exists() {
    [ -d "$1" ]
}

# 获取时间戳
get_timestamp() {
    date +%s
}

# 获取格式化时间
get_datetime() {
    date '+%Y-%m-%d %H:%M:%S'
}

# URL 编码
url_encode() {
    local string="$1"
    local strlen=${#string}
    local encoded=""
    local pos c o
    
    for (( pos=0 ; pos<strlen ; pos++ )); do
        c=${string:$pos:1}
        case "$c" in
            [-_.~a-zA-Z0-9] ) o="${c}" ;;
            * ) printf -v o '%%%02x' "'$c"
        esac
        encoded+="${o}"
    done
    echo "${encoded}"
}

# 解析 URL
parse_url() {
    local url="$1"
    local component="${2:-full}"
    
    # 使用正则表达式解析 URL
    if [[ "$url" =~ ^(https?://)?(([^:@]+):([^@]+)@)?([^:/]+)(:([0-9]+))?(/(.*))?$ ]]; then
        local protocol="${BASH_REMATCH[1]:-http://}"
        local username="${BASH_REMATCH[3]}"
        local password="${BASH_REMATCH[4]}"
        local host="${BASH_REMATCH[5]}"
        local port="${BASH_REMATCH[7]:-9200}"
        local path="${BASH_REMATCH[9]}"
        
        case "$component" in
            protocol) echo "$protocol" ;;
            username) echo "$username" ;;
            password) echo "$password" ;;
            host) echo "$host" ;;
            port) echo "$port" ;;
            path) echo "$path" ;;
            base) echo "${protocol}${host}:${port}" ;;
            auth) [ -n "$username" ] && echo "${username}:${password}" ;;
            full) echo "$url" ;;
        esac
    else
        echo "$url"
    fi
}

# 验证 URL 格式
validate_url() {
    local url="$1"
    if [[ "$url" =~ ^https?://[^/]+ ]]; then
        return 0
    else
        return 1
    fi
}

# 测试 ES 连接
test_es_connection() {
    local url="$1"
    local timeout="${2:-5}"
    
    debug "测试连接: $url"
    
    local response
    response=$(curl -s -w "\n%{http_code}" --max-time "$timeout" "$url" 2>/dev/null)
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    debug "HTTP 状态码: $http_code"
    
    if [ "$http_code" = "200" ]; then
        return 0
    elif [ "$http_code" = "401" ]; then
        error "认证失败 (401)"
        return 1
    elif [ "$http_code" = "403" ]; then
        error "权限不足 (403)"
        return 1
    elif [ -z "$http_code" ]; then
        error "连接超时或无法连接"
        return 1
    else
        error "连接失败 (HTTP $http_code)"
        return 1
    fi
}

# 获取索引信息
get_index_info() {
    local es_url="$1"
    local index_name="$2"
    
    local response
    response=$(curl -s "${es_url}/${index_name}/_stats" 2>/dev/null)
    
    if [ $? -eq 0 ] && echo "$response" | grep -q '"_shards"'; then
        echo "$response"
        return 0
    else
        return 1
    fi
}

# 获取索引文档数
get_index_doc_count() {
    local es_url="$1"
    local index_name="$2"
    
    local stats
    stats=$(get_index_info "$es_url" "$index_name")
    
    if [ $? -eq 0 ]; then
        if command_exists jq; then
            echo "$stats" | jq -r '._all.primaries.docs.count // 0'
        elif command_exists python3; then
            echo "$stats" | python3 -c "import sys, json; print(json.load(sys.stdin)['_all']['primaries']['docs']['count'])" 2>/dev/null || echo "0"
        else
            # 简单的文本解析
            echo "$stats" | grep -oP '"count"\s*:\s*\K\d+' | head -1
        fi
    else
        echo "0"
    fi
}

# 获取索引大小
get_index_size() {
    local es_url="$1"
    local index_name="$2"
    
    local stats
    stats=$(get_index_info "$es_url" "$index_name")
    
    if [ $? -eq 0 ]; then
        if command_exists jq; then
            echo "$stats" | jq -r '._all.primaries.store.size_in_bytes // 0'
        elif command_exists python3; then
            echo "$stats" | python3 -c "import sys, json; print(json.load(sys.stdin)['_all']['primaries']['store']['size_in_bytes'])" 2>/dev/null || echo "0"
        else
            echo "0"
        fi
    else
        echo "0"
    fi
}

# 检查索引是否存在
check_index_exists() {
    local es_url="$1"
    local index_name="$2"
    
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "${es_url}/${index_name}" 2>/dev/null)
    
    if [ "$http_code" = "200" ]; then
        return 0
    else
        return 1
    fi
}

# 确认操作
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    
    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n] "
    else
        prompt="$prompt [y/N] "
    fi
    
    read -p "$prompt" -n 1 -r
    echo
    
    if [ "$default" = "y" ]; then
        [[ ! $REPLY =~ ^[Nn]$ ]]
    else
        [[ $REPLY =~ ^[Yy]$ ]]
    fi
}

# 清理临时文件
cleanup() {
    local files=("$@")
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
            debug "已清理临时文件: $file"
        fi
    done
}

# 创建目录
ensure_dir() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        debug "已创建目录: $dir"
    fi
}

# 获取 PID 文件路径
get_pid_file() {
    echo "${SCRIPT_DIR}/elasticdump.${1}.pid"
}

# 获取日志文件路径
get_log_file() {
    echo "${SCRIPT_DIR}/elasticdump.${1}.log"
}

# 获取进度文件路径
get_progress_file() {
    echo "${SCRIPT_DIR}/elasticdump.${1}.progress"
}

# 获取 PIT 文件路径
get_pit_file() {
    echo "${SCRIPT_DIR}/elasticdump.${1}.pit"
}

# 检查进程是否运行
is_process_running() {
    local pid="$1"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# 获取任务 PID
get_task_pid() {
    local index_name="$1"
    local pid_file
    pid_file=$(get_pid_file "$index_name")
    
    if [ -f "$pid_file" ]; then
        cat "$pid_file"
    fi
}

# 检查任务是否运行
is_task_running() {
    local index_name="$1"
    local pid
    pid=$(get_task_pid "$index_name")
    
    if [ -n "$pid" ]; then
        is_process_running "$pid"
    else
        return 1
    fi
}
