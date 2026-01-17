#!/bin/bash

# 核心 dump 逻辑模块

# 开始 dump
start_dump() {
    local from="$1"
    local to="$2"
    local index_name="$3"
    local output_index="$4"
    local limit="$5"
    local mode="$6"
    local shard_id="$7"
    local offset="$8"
    local use_source_mapping="$9"
    local ignore_errors="${10}"
    local quiet="${11}"
    
    # 检查是否已经在运行
    if is_task_running "$index_name"; then
        error "任务已在运行: $index_name"
        local pid
        pid=$(get_task_pid "$index_name")
        echo "PID: $pid"
        exit 1
    fi
    
    # 准备日志和进度文件
    local log_file
    log_file=$(get_log_file "$index_name")
    
    local progress_file
    progress_file=$(get_progress_file "$index_name")
    
    local pid_file
    pid_file=$(get_pid_file "$index_name")
    
    # 创建后台任务
    section "启动任务"
    
    echo "  索引:     $index_name → $output_index"
    echo "  模式:     $mode"
    echo "  批量:     $limit"
    echo "  日志:     $log_file"
    echo ""
    
    # 构建 elasticdump 命令
    local cmd="elasticdump"
    
    # 输入输出
    cmd="$cmd --input=${from}/${index_name}"
    cmd="$cmd --output=${to}/${output_index}"
    
    # 类型
    cmd="$cmd --type=data"
    
    # 批量大小
    cmd="$cmd --limit=${limit}"
    
    # 超时和重试
    cmd="$cmd --timeout=${DEFAULT_TIMEOUT}"
    cmd="$cmd --maxSockets=10"
    cmd="$cmd --retryAttempts=${DEFAULT_RETRY}"
    cmd="$cmd --retryDelay=5000"
    
    # 错误处理
    if [ "$ignore_errors" = "true" ]; then
        cmd="$cmd --ignoreErrors=true"
    fi
    
    # 模式选择
    if [ "$mode" = "search_after" ]; then
        cmd="$cmd --searchWithTemplate='{\"size\":{{limit}},\"query\":{\"match_all\":{}},\"search_after\":{{lastHit}},\"sort\":[{\"_id\":\"asc\"}]}'"
        cmd="$cmd --searchBody='{\"query\":{\"match_all\":{}}}'"
    else
        # scroll 模式
        cmd="$cmd --scrollTime=${DEFAULT_SCROLL_TIME}"
        
        # 分片过滤
        if [ -n "$shard_id" ]; then
            cmd="$cmd --searchBody='{\"query\":{\"match_all\":{}}}'"
            cmd="$cmd --preference=_shards:${shard_id}"
        fi
    fi
    
    # 偏移量（断点续传）
    if [ -n "$offset" ]; then
        cmd="$cmd --offset=${offset}"
    fi
    
    # 从源获取 mapping
    if [ "$use_source_mapping" = "true" ]; then
        info "从源索引获取 mapping..."
        
        # 先导出 mapping
        local mapping_cmd="elasticdump"
        mapping_cmd="$mapping_cmd --input=${from}/${index_name}"
        mapping_cmd="$mapping_cmd --output=${to}/${output_index}"
        mapping_cmd="$mapping_cmd --type=mapping"
        
        debug "执行: $mapping_cmd"
        
        if ! eval "$mapping_cmd" >> "$log_file" 2>&1; then
            error "导出 mapping 失败"
            exit 1
        fi
        
        info "Mapping 导出成功"
    fi
    
    # 启动后台任务
    debug "执行: $cmd"
    
    # 使用 nohup 后台执行
    nohup bash -c "
        # 记录开始时间
        echo \"[$(get_datetime)] 开始导出\" >> '$log_file'
        echo \"命令: $cmd\" >> '$log_file'
        echo \"\" >> '$log_file'
        
        # 执行 elasticdump
        $cmd 2>&1 | while IFS= read -r line; do
            echo \"\$line\" >> '$log_file'
            
            # 提取进度信息
            if [[ \"\$line\" =~ ([0-9]+).*objects ]]; then
                count=\"\${BASH_REMATCH[1]}\"
                echo \"\${count}|$(get_timestamp)\" > '$progress_file'
            fi
        done
        
        # 记录结束
        exit_code=\${PIPESTATUS[0]}
        echo \"\" >> '$log_file'
        echo \"[$(get_datetime)] 任务结束，退出码: \$exit_code\" >> '$log_file'
        
        # 清理 PID 文件
        rm -f '$pid_file'
        
        exit \$exit_code
    " > /dev/null 2>&1 &
    
    local pid=$!
    
    # 保存 PID
    echo "$pid" > "$pid_file"
    
    success "任务已启动"
    
    echo "  PID:      $pid"
    echo "  日志:     $log_file"
    echo ""
    echo "查看进度:"
    echo "  elasticdump-easy status $index_name"
    echo ""
    echo "查看日志:"
    echo "  tail -f $log_file"
    echo ""
    echo "停止任务:"
    echo "  elasticdump-easy stop $index_name"
    echo ""
    
    # 如果不是静默模式，等待一会儿显示初始进度
    if [ "$quiet" != "true" ]; then
        sleep 3
        
        if is_task_running "$index_name"; then
            info "任务运行正常"
            
            # 显示最新日志
            if [ -f "$log_file" ]; then
                echo ""
                echo "最新日志:"
                tail -n 5 "$log_file" | sed 's/^/  /'
            fi
        else
            error "任务启动失败"
            
            if [ -f "$log_file" ]; then
                echo ""
                echo "错误日志:"
                tail -n 10 "$log_file" | sed 's/^/  /'
            fi
            
            exit 1
        fi
    fi
}

# 停止 dump
stop_dump() {
    local index_name="$1"
    
    if ! is_task_running "$index_name"; then
        warn "任务未运行: $index_name"
        return 1
    fi
    
    local pid
    pid=$(get_task_pid "$index_name")
    
    info "停止任务: $index_name (PID: $pid)"
    
    # 发送 SIGTERM
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
    rm -f "$(get_pid_file "$index_name")"
    
    success "任务已停止"
}

# 获取 dump 进度
get_dump_progress() {
    local index_name="$1"
    
    local progress_file
    progress_file=$(get_progress_file "$index_name")
    
    if [ -f "$progress_file" ]; then
        cat "$progress_file"
    fi
}

# 保存 dump 进度
save_dump_progress() {
    local index_name="$1"
    local count="$2"
    
    local progress_file
    progress_file=$(get_progress_file "$index_name")
    
    local timestamp
    timestamp=$(get_timestamp)
    
    echo "${count}|${timestamp}" > "$progress_file"
}

# 清理 dump 文件
cleanup_dump() {
    local index_name="$1"
    
    local pid_file
    pid_file=$(get_pid_file "$index_name")
    
    local progress_file
    progress_file=$(get_progress_file "$index_name")
    
    local pit_file
    pit_file=$(get_pit_file "$index_name")
    
    rm -f "$pid_file" "$progress_file" "$pit_file"
    
    debug "已清理任务文件: $index_name"
}
