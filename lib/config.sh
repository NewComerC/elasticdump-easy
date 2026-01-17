#!/bin/bash

# 配置管理模块

# 默认配置
DEFAULT_FROM="http://localhost:9200"
DEFAULT_TO="http://localhost:9200"
DEFAULT_LIMIT=""  # 自动选择
DEFAULT_MODE=""   # 自动选择
DEFAULT_TIMEOUT=900000  # 15分钟
DEFAULT_RETRY=10
DEFAULT_SCROLL_TIME="30m"

# 配置目录
CONFIG_DIR="${HOME}/.elasticdump-easy"
PROFILES_DIR="${CONFIG_DIR}/profiles"

# 初始化配置目录
init_config_dir() {
    ensure_dir "$CONFIG_DIR"
    ensure_dir "$PROFILES_DIR"
}

# 加载配置文件
load_config() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        error "配置文件不存在: $config_file"
        return 1
    fi
    
    if ! command_exists jq && ! command_exists python3; then
        error "需要 jq 或 python3 来解析配置文件"
        return 1
    fi
    
    debug "加载配置文件: $config_file"
    
    # 使用 jq 或 python3 解析 JSON
    if command_exists jq; then
        FROM=$(jq -r '.from // empty' "$config_file")
        TO=$(jq -r '.to // empty' "$config_file")
        LIMIT=$(jq -r '.limit // empty' "$config_file")
        MODE=$(jq -r '.mode // empty' "$config_file")
    elif command_exists python3; then
        local parsed
        parsed=$(python3 -c "
import sys, json
try:
    with open('$config_file') as f:
        config = json.load(f)
    print(config.get('from', ''))
    print(config.get('to', ''))
    print(config.get('limit', ''))
    print(config.get('mode', ''))
except:
    sys.exit(1)
" 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            FROM=$(echo "$parsed" | sed -n '1p')
            TO=$(echo "$parsed" | sed -n '2p')
            LIMIT=$(echo "$parsed" | sed -n '3p')
            MODE=$(echo "$parsed" | sed -n '4p')
        fi
    fi
    
    return 0
}

# 加载 profile
load_profile() {
    local profile_name="$1"
    local profile_file="${PROFILES_DIR}/${profile_name}.json"
    
    if [ ! -f "$profile_file" ]; then
        error "Profile 不存在: $profile_name"
        return 1
    fi
    
    info "加载 profile: $profile_name"
    load_config "$profile_file"
}

# 保存 profile
save_profile() {
    local profile_name="$1"
    local from="$2"
    local to="$3"
    local profile_file="${PROFILES_DIR}/${profile_name}.json"
    
    init_config_dir
    
    cat > "$profile_file" << EOF
{
  "from": "$from",
  "to": "$to",
  "created_at": "$(get_datetime)"
}
EOF
    
    info "已保存 profile: $profile_name"
    return 0
}

# 列出所有 profiles
list_profiles() {
    init_config_dir
    
    if [ ! "$(ls -A "$PROFILES_DIR" 2>/dev/null)" ]; then
        warn "没有保存的 profiles"
        return 1
    fi
    
    section "已保存的 Profiles"
    
    for profile_file in "$PROFILES_DIR"/*.json; do
        if [ -f "$profile_file" ]; then
            local profile_name=$(basename "$profile_file" .json)
            echo "  • $profile_name"
            
            if command_exists jq; then
                local from=$(jq -r '.from' "$profile_file")
                local to=$(jq -r '.to' "$profile_file")
                echo "    From: $from"
                echo "    To:   $to"
            fi
        fi
    done
    
    return 0
}

# 智能选择参数
auto_select_params() {
    local doc_count="$1"
    local size_bytes="$2"
    
    # 根据文档数和大小选择最佳参数
    if [ "$doc_count" -lt 100000 ]; then
        # 小索引: < 10万文档
        LIMIT="${LIMIT:-2000}"
        MODE="${MODE:-scroll}"
        debug "小索引模式: limit=$LIMIT, mode=$MODE"
    elif [ "$doc_count" -lt 1000000 ]; then
        # 中等索引: 10万 - 100万文档
        LIMIT="${LIMIT:-1000}"
        MODE="${MODE:-scroll}"
        debug "中等索引模式: limit=$LIMIT, mode=$MODE"
    elif [ "$doc_count" -lt 10000000 ]; then
        # 大索引: 100万 - 1000万文档
        LIMIT="${LIMIT:-1000}"
        MODE="${MODE:-search_after}"
        debug "大索引模式: limit=$LIMIT, mode=$MODE"
    else
        # 超大索引: > 1000万文档
        LIMIT="${LIMIT:-500}"
        MODE="${MODE:-search_after}"
        warn "检测到超大索引，建议使用 --auto-shard 进行分片导出"
        debug "超大索引模式: limit=$LIMIT, mode=$MODE"
    fi
}

# 构建 ES URL
build_es_url() {
    local base_url="$1"
    local index_name="$2"
    
    # 移除末尾的斜杠
    base_url="${base_url%/}"
    
    # 如果 URL 中已经包含索引名，直接返回
    if [[ "$base_url" =~ /[^/]+$ ]] && [ -n "$index_name" ]; then
        echo "$base_url"
    else
        echo "${base_url}/${index_name}"
    fi
}

# 解析命令行 URL（支持简写）
parse_cli_url() {
    local url="$1"
    
    # 如果没有协议，添加 http://
    if [[ ! "$url" =~ ^https?:// ]]; then
        url="http://${url}"
    fi
    
    # 如果没有端口，添加默认端口 9200
    if [[ ! "$url" =~ :[0-9]+(/|$) ]]; then
        # 提取协议、认证和主机部分
        if [[ "$url" =~ ^(https?://)?(([^@]+)@)?([^/]+)(/.*)? ]]; then
            local protocol="${BASH_REMATCH[1]:-http://}"
            local auth="${BASH_REMATCH[3]}"
            local host="${BASH_REMATCH[4]}"
            local path="${BASH_REMATCH[5]}"
            
            if [ -n "$auth" ]; then
                url="${protocol}${auth}@${host}:9200${path}"
            else
                url="${protocol}${host}:9200${path}"
            fi
        fi
    fi
    
    echo "$url"
}

# 验证配置
validate_config() {
    local from="$1"
    local to="$2"
    
    if [ -z "$from" ]; then
        error "缺少源 ES 地址 (--from)"
        return 1
    fi
    
    if [ -z "$to" ]; then
        error "缺少目标 ES 地址 (--to)"
        return 1
    fi
    
    if ! validate_url "$from"; then
        error "无效的源 ES 地址: $from"
        return 1
    fi
    
    if ! validate_url "$to"; then
        error "无效的目标 ES 地址: $to"
        return 1
    fi
    
    return 0
}

# 显示配置信息
show_config() {
    local from="$1"
    local to="$2"
    local index_name="$3"
    local output_index="$4"
    
    section "配置信息"
    echo "  源地址:     $from"
    echo "  源索引:     $index_name"
    echo "  目标地址:   $to"
    echo "  目标索引:   $output_index"
    echo "  批量大小:   ${LIMIT:-自动}"
    echo "  Dump 模式:  ${MODE:-自动}"
}
