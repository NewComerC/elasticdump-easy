#!/bin/bash

# 进度管理模块

# 显示实时进度
show_realtime_progress() {
    local index_name="$1"
    local total_docs="$2"
    
    local progress_file
    progress_file=$(get_progress_file "$index_name")
    
    local start_time
    start_time=$(get_timestamp)
    
    echo ""
    section "导出进度"
    echo ""
    
    while is_task_running "$index_name"; do
        if [ -f "$progress_file" ]; then
            local progress
            progress=$(cat "$progress_file")
            
            local current=$(echo "$progress" | cut -d'|' -f1)
            local timestamp=$(echo "$progress" | cut -d'|' -f2)
            
            if [ -n "$current" ] && [ "$current" -gt 0 ]; then
                # 计算进度
                local percentage=0
                if [ "$total_docs" -gt 0 ]; then
                    percentage=$((current * 100 / total_docs))
                fi
                
                # 计算速度
                local now
                now=$(get_timestamp)
                local elapsed=$((now - start_time))
                
                local speed=0
                if [ "$elapsed" -gt 0 ]; then
                    speed=$((current / elapsed))
                fi
                
                # 计算剩余时间
                local remaining=""
                if [ "$speed" -gt 0 ] && [ "$total_docs" -gt 0 ]; then
                    local remaining_docs=$((total_docs - current))
                    local remaining_seconds=$((remaining_docs / speed))
                    remaining=$(format_time "$remaining_seconds")
                fi
                
                # 显示进度条
                printf "\r  "
                show_progress "$current" "$total_docs"
                
                if [ -n "$remaining" ]; then
                    printf "  速度: %'d docs/s  剩余: %s" "$speed" "$remaining"
                else
                    printf "  速度: %'d docs/s" "$speed"
                fi
            fi
        fi
        
        sleep 2
    done
    
    echo ""
    echo ""
}

# 监控进度（后台）
monitor_progress() {
    local index_name="$1"
    local log_file="$2"
    
    local progress_file
    progress_file=$(get_progress_file "$index_name")
    
    # 从日志中提取进度
    tail -f "$log_file" 2>/dev/null | while IFS= read -r line; do
        # elasticdump 输出格式: "Wrote X objects"
        if [[ "$line" =~ ([0-9]+).*objects ]]; then
            local count="${BASH_REMATCH[1]}"
            save_dump_progress "$index_name" "$count"
        fi
        
        # 检查是否完成
        if [[ "$line" =~ "Complete" ]] || [[ "$line" =~ "finished" ]]; then
            break
        fi
    done
}

# 计算预估时间
estimate_time() {
    local current="$1"
    local total="$2"
    local elapsed="$3"
    
    if [ "$current" -eq 0 ] || [ "$elapsed" -eq 0 ]; then
        echo "计算中..."
        return
    fi
    
    local speed=$((current / elapsed))
    local remaining=$((total - current))
    local remaining_seconds=$((remaining / speed))
    
    format_time "$remaining_seconds"
}

# 显示进度摘要
show_progress_summary() {
    local index_name="$1"
    local total_docs="$2"
    
    local progress_file
    progress_file=$(get_progress_file "$index_name")
    
    if [ ! -f "$progress_file" ]; then
        warn "没有进度信息"
        return 1
    fi
    
    local progress
    progress=$(cat "$progress_file")
    
    local current=$(echo "$progress" | cut -d'|' -f1)
    local timestamp=$(echo "$progress" | cut -d'|' -f2)
    
    echo "  已导出:   $(printf "%'d" "$current") / $(printf "%'d" "$total_docs") 文档"
    
    if [ "$total_docs" -gt 0 ]; then
        local percentage=$((current * 100 / total_docs))
        echo "  进度:     ${percentage}%"
    fi
    
    if [ -n "$timestamp" ]; then
        local now
        now=$(get_timestamp)
        local last_update=$((now - timestamp))
        echo "  最后更新: $(format_time "$last_update") 前"
    fi
}
