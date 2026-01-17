#!/bin/bash

# CLI 命令处理模块

# dump 命令
cmd_dump() {
    local INDEX_NAME=""
    local OUTPUT_INDEX=""
    local FROM="$DEFAULT_FROM"
    local TO="$DEFAULT_TO"
    local CONFIG_FILE=""
    local PROFILE=""
    local SHARD_ID=""
    local OFFSET=""
    local USE_SOURCE_MAPPING="false"
    local IGNORE_ERRORS="true"
    local QUIET="false"
    local AUTO_SHARD="false"
    
    # 解析参数
    while [ $# -gt 0 ]; do
        case "$1" in
            --from)
                FROM=$(parse_cli_url "$2")
                shift 2
                ;;
            --to)
                TO=$(parse_cli_url "$2")
                shift 2
                ;;
            --output-index|-O)
                OUTPUT_INDEX="$2"
                shift 2
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --profile)
                PROFILE="$2"
                shift 2
                ;;
            --limit|-l)
                LIMIT="$2"
                shift 2
                ;;
            --mode)
                MODE="$2"
                shift 2
                ;;
            --shard)
                SHARD_ID="$2"
                shift 2
                ;;
            --offset)
                OFFSET="$2"
                shift 2
                ;;
            --use-source-mapping)
                USE_SOURCE_MAPPING="true"
                shift
                ;;
            --ignore-errors)
                IGNORE_ERRORS="true"
                shift
                ;;
            --no-ignore-errors)
                IGNORE_ERRORS="false"
                shift
                ;;
            --quiet|-q)
                QUIET="true"
                shift
                ;;
            --debug|-d)
                DEBUG_MODE="true"
                shift
                ;;
            --auto-shard)
                AUTO_SHARD="true"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            -*)
                error "未知选项: $1"
                echo "使用 --help 查看帮助"
                exit 1
                ;;
            *)
                if [ -z "$INDEX_NAME" ]; then
                    INDEX_NAME="$1"
                else
                    error "多余的参数: $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # 检查必需参数
    if [ -z "$INDEX_NAME" ]; then
        error "请指定索引名称"
        echo ""
        echo "用法: elasticdump-easy dump <索引名> [选项]"
        echo "使用 --help 查看完整帮助"
        exit 1
    fi
    
    # 设置输出索引名
    OUTPUT_INDEX="${OUTPUT_INDEX:-$INDEX_NAME}"
    
    # 加载配置
    if [ -n "$CONFIG_FILE" ]; then
        load_config "$CONFIG_FILE" || exit 1
    elif [ -n "$PROFILE" ]; then
        load_profile "$PROFILE" || exit 1
    fi
    
    # 应用默认值
    FROM="${FROM:-$DEFAULT_FROM}"
    TO="${TO:-$DEFAULT_TO}"
    
    # 验证配置
    validate_config "$FROM" "$TO" || exit 1
    
    # 提取基础 URL（移除索引名）
    local FROM_BASE=$(echo "$FROM" | sed 's|/[^/]*$||')
    local TO_BASE=$(echo "$TO" | sed 's|/[^/]*$||')
    
    # 如果 FROM 中包含索引名，使用它
    if [[ "$FROM" =~ /([^/]+)$ ]]; then
        local from_index="${BASH_REMATCH[1]}"
        if [ "$from_index" != "$FROM_BASE" ] && [ "$from_index" != "9200" ]; then
            INDEX_NAME="$from_index"
        fi
    fi
    
    # 如果 TO 中包含索引名，使用它
    if [[ "$TO" =~ /([^/]+)$ ]]; then
        local to_index="${BASH_REMATCH[1]}"
        if [ "$to_index" != "$TO_BASE" ] && [ "$to_index" != "9200" ]; then
            OUTPUT_INDEX="$to_index"
        fi
    fi
    
    # 重新构建完整 URL
    FROM="${FROM_BASE}"
    TO="${TO_BASE}"
    
    # 显示欢迎信息
    if [ "$QUIET" != "true" ]; then
        echo ""
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║         Elasticdump Easy - ES 数据迁移工具                ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""
    fi
    
    # 测试连接
    section "测试连接"
    
    echo -n "  检查源 ES... "
    if test_es_connection "$FROM"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        error "无法连接到源 ES: $FROM"
        exit 1
    fi
    
    echo -n "  检查目标 ES... "
    if test_es_connection "$TO"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        error "无法连接到目标 ES: $TO"
        exit 1
    fi
    
    # 检查索引
    echo -n "  检查源索引... "
    if check_index_exists "$FROM" "$INDEX_NAME"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        error "源索引不存在: $INDEX_NAME"
        exit 1
    fi
    
    # 获取索引信息
    section "索引信息"
    
    local doc_count
    doc_count=$(get_index_doc_count "$FROM" "$INDEX_NAME")
    
    local size_bytes
    size_bytes=$(get_index_size "$FROM" "$INDEX_NAME")
    
    local size_human
    size_human=$(format_size "$size_bytes")
    
    echo "  索引名称:   $INDEX_NAME"
    echo "  文档数量:   $(printf "%'d" "$doc_count")"
    echo "  索引大小:   $size_human"
    
    # 智能选择参数
    if [ -z "$LIMIT" ] || [ -z "$MODE" ]; then
        auto_select_params "$doc_count" "$size_bytes"
    fi
    
    # 显示配置
    show_config "$FROM" "$TO" "$INDEX_NAME" "$OUTPUT_INDEX"
    
    # 确认开始
    if [ "$QUIET" != "true" ]; then
        echo ""
        if ! confirm "是否开始导出?" "y"; then
            warn "已取消"
            exit 0
        fi
    fi
    
    # 开始 dump
    start_dump "$FROM" "$TO" "$INDEX_NAME" "$OUTPUT_INDEX" \
        "$LIMIT" "$MODE" "$SHARD_ID" "$OFFSET" \
        "$USE_SOURCE_MAPPING" "$IGNORE_ERRORS" "$QUIET"
}

# stop 命令
cmd_stop() {
    local INDEX_NAME="$1"
    
    if [ -z "$INDEX_NAME" ]; then
        error "请指定索引名称"
        echo "用法: elasticdump-easy stop <索引名>"
        exit 1
    fi
    
    if ! is_task_running "$INDEX_NAME"; then
        warn "任务未运行: $INDEX_NAME"
        exit 0
    fi
    
    local pid
    pid=$(get_task_pid "$INDEX_NAME")
    
    section "停止任务: $INDEX_NAME"
    
    echo "  PID: $pid"
    
    if confirm "确认停止?" "y"; then
        kill "$pid" 2>/dev/null
        
        # 等待进程结束
        local count=0
        while is_process_running "$pid" && [ $count -lt 10 ]; do
            sleep 1
            count=$((count + 1))
        done
        
        if is_process_running "$pid"; then
            warn "进程未响应，强制终止"
            kill -9 "$pid" 2>/dev/null
        fi
        
        # 清理 PID 文件
        rm -f "$(get_pid_file "$INDEX_NAME")"
        
        success "任务已停止"
    else
        warn "已取消"
    fi
}

# status 命令
cmd_status() {
    local INDEX_NAME="$1"
    
    if [ -n "$INDEX_NAME" ]; then
        # 显示单个任务状态
        show_task_status "$INDEX_NAME"
    else
        # 显示所有任务状态
        cmd_list
    fi
}

# list 命令
cmd_list() {
    section "任务列表"
    
    local found=false
    
    for pid_file in "${SCRIPT_DIR}"/elasticdump.*.pid; do
        if [ -f "$pid_file" ]; then
            local index_name=$(basename "$pid_file" .pid | sed 's/^elasticdump\.//')
            found=true
            
            echo ""
            show_task_status "$index_name"
        fi
    done
    
    if [ "$found" = false ]; then
        echo "  没有运行中的任务"
    fi
    
    echo ""
}

# resume 命令
cmd_resume() {
    local INDEX_NAME="$1"
    
    if [ -z "$INDEX_NAME" ]; then
        error "请指定索引名称"
        echo "用法: elasticdump-easy resume <索引名>"
        exit 1
    fi
    
    local progress_file
    progress_file=$(get_progress_file "$INDEX_NAME")
    
    if [ ! -f "$progress_file" ]; then
        error "没有找到进度文件: $INDEX_NAME"
        echo "该任务可能没有中断，或进度文件已被删除"
        exit 1
    fi
    
    # 读取进度
    local progress
    progress=$(cat "$progress_file")
    local offset=$(echo "$progress" | cut -d'|' -f1)
    
    info "从第 $offset 个文档继续"
    
    # TODO: 实现断点续传逻辑
    warn "断点续传功能开发中"
}

# test 命令
cmd_test() {
    local FROM="$DEFAULT_FROM"
    local TO="$DEFAULT_TO"
    
    # 解析参数
    while [ $# -gt 0 ]; do
        case "$1" in
            --from)
                FROM=$(parse_cli_url "$2")
                shift 2
                ;;
            --to)
                TO=$(parse_cli_url "$2")
                shift 2
                ;;
            *)
                error "未知选项: $1"
                exit 1
                ;;
        esac
    done
    
    section "测试连接"
    
    echo ""
    echo "源 ES: $FROM"
    if test_es_connection "$FROM"; then
        success "连接成功"
    else
        error "连接失败"
        exit 1
    fi
    
    echo ""
    echo "目标 ES: $TO"
    if test_es_connection "$TO"; then
        success "连接成功"
    else
        error "连接失败"
        exit 1
    fi
}

# init 命令
cmd_init() {
    section "配置向导"
    
    echo ""
    echo "欢迎使用 Elasticdump Easy!"
    echo "让我们配置您的第一个 profile"
    echo ""
    
    # 输入 profile 名称
    read -p "Profile 名称 (例如: prod): " profile_name
    
    if [ -z "$profile_name" ]; then
        error "Profile 名称不能为空"
        exit 1
    fi
    
    # 输入源 ES
    read -p "源 ES 地址 (例如: http://user:pass@host:9200): " from_url
    from_url=$(parse_cli_url "$from_url")
    
    # 测试源连接
    echo -n "测试源连接... "
    if test_es_connection "$from_url"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        error "无法连接到源 ES"
        exit 1
    fi
    
    # 输入目标 ES
    read -p "目标 ES 地址 (例如: http://user:pass@host:9200): " to_url
    to_url=$(parse_cli_url "$to_url")
    
    # 测试目标连接
    echo -n "测试目标连接... "
    if test_es_connection "$to_url"; then
        echo -e "${GREEN}✓${NC}"
    else
        echo -e "${RED}✗${NC}"
        error "无法连接到目标 ES"
        exit 1
    fi
    
    # 保存 profile
    save_profile "$profile_name" "$from_url" "$to_url"
    
    echo ""
    success "配置完成!"
    echo ""
    echo "现在您可以使用以下命令开始导出:"
    echo "  elasticdump-easy dump <索引名> --profile $profile_name"
    echo ""
}

# 显示任务状态
show_task_status() {
    local index_name="$1"
    local pid
    pid=$(get_task_pid "$index_name")
    
    echo "  索引: $index_name"
    
    if [ -n "$pid" ] && is_process_running "$pid"; then
        echo "  状态: ${GREEN}运行中${NC}"
        echo "  PID:  $pid"
        
        # 显示进度
        local progress_file
        progress_file=$(get_progress_file "$index_name")
        
        if [ -f "$progress_file" ]; then
            local progress
            progress=$(cat "$progress_file")
            local count=$(echo "$progress" | cut -d'|' -f1)
            local timestamp=$(echo "$progress" | cut -d'|' -f2)
            
            echo "  进度: $(printf "%'d" "$count") 文档"
            
            if [ -n "$timestamp" ]; then
                local now
                now=$(get_timestamp)
                local elapsed=$((now - timestamp))
                echo "  更新: $(format_time "$elapsed") 前"
            fi
        fi
        
        # 显示日志文件
        local log_file
        log_file=$(get_log_file "$index_name")
        if [ -f "$log_file" ]; then
            echo "  日志: $log_file"
        fi
    else
        echo "  状态: ${YELLOW}已停止${NC}"
        
        if [ -n "$pid" ]; then
            echo "  PID:  $pid (已退出)"
        fi
    fi
}
