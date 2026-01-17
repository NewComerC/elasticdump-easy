#!/bin/bash

# 错误处理模块

# 错误代码定义
ERROR_CONNECTION=1
ERROR_AUTH=2
ERROR_INDEX_NOT_FOUND=3
ERROR_PERMISSION=4
ERROR_TIMEOUT=5
ERROR_UNKNOWN=99

# 显示错误详情和解决方案
show_error_detail() {
    local error_type="$1"
    local context="$2"
    
    case "$error_type" in
        connection)
            echo ""
            error "连接失败"
            echo ""
            echo "  地址: $context"
            echo ""
            echo "💡 可能的原因:"
            echo "  1. ES 服务未运行"
            echo "  2. 网络连接问题"
            echo "  3. 防火墙阻止连接"
            echo "  4. URL 或端口错误"
            echo ""
            echo "🔧 解决方案:"
            echo "  • 检查 ES 服务状态"
            echo "  • 验证网络连接: ping $context"
            echo "  • 检查防火墙规则"
            echo "  • 确认 URL 格式正确"
            echo ""
            echo "测试连接:"
            echo "  elasticdump-easy test --from $context"
            echo ""
            ;;
            
        auth)
            echo ""
            error "认证失败 (401)"
            echo ""
            echo "  地址: $context"
            echo ""
            echo "💡 可能的原因:"
            echo "  1. 用户名或密码错误"
            echo "  2. 用户不存在"
            echo "  3. 认证方式不正确"
            echo ""
            echo "🔧 解决方案:"
            echo "  • 检查用户名和密码"
            echo "  • 确认用户已创建"
            echo "  • 验证认证配置"
            echo ""
            echo "URL 格式:"
            echo "  http://username:password@host:9200"
            echo ""
            ;;
            
        permission)
            echo ""
            error "权限不足 (403)"
            echo ""
            echo "  地址: $context"
            echo ""
            echo "💡 可能的原因:"
            echo "  1. 用户没有读取权限"
            echo "  2. 用户没有写入权限"
            echo "  3. IP 白名单限制"
            echo ""
            echo "🔧 解决方案:"
            echo "  • 检查用户权限配置"
            echo "  • 确认索引访问权限"
            echo "  • 检查 IP 白名单设置"
            echo ""
            ;;
            
        index_not_found)
            echo ""
            error "索引不存在"
            echo ""
            echo "  索引名: $context"
            echo ""
            echo "💡 可能的原因:"
            echo "  1. 索引名拼写错误"
            echo "  2. 索引已被删除"
            echo "  3. 连接到错误的集群"
            echo ""
            echo "🔧 解决方案:"
            echo "  • 检查索引名是否正确"
            echo "  • 列出所有索引"
            echo "  • 确认连接的集群"
            echo ""
            echo "列出索引:"
            echo "  curl -X GET \"http://host:9200/_cat/indices?v\""
            echo ""
            ;;
            
        timeout)
            echo ""
            error "操作超时"
            echo ""
            echo "  上下文: $context"
            echo ""
            echo "💡 可能的原因:"
            echo "  1. 索引数据量太大"
            echo "  2. 网络速度慢"
            echo "  3. ES 集群负载高"
            echo "  4. 文档过大"
            echo ""
            echo "🔧 解决方案:"
            echo "  • 减小批量大小: --limit=500"
            echo "  • 使用分片导出: --shard=0"
            echo "  • 检查网络质量"
            echo "  • 检查 ES 集群状态"
            echo ""
            ;;
            
        *)
            echo ""
            error "未知错误"
            echo ""
            echo "  详情: $context"
            echo ""
            echo "🔧 建议:"
            echo "  • 查看详细日志"
            echo "  • 使用 --debug 模式重试"
            echo "  • 检查 ES 集群状态"
            echo ""
            ;;
    esac
}

# 分析日志错误
analyze_log_error() {
    local log_file="$1"
    
    if [ ! -f "$log_file" ]; then
        return 1
    fi
    
    # 检查常见错误模式
    if grep -q "ECONNREFUSED" "$log_file"; then
        show_error_detail "connection" "$(grep "ECONNREFUSED" "$log_file" | head -1)"
        return $ERROR_CONNECTION
    elif grep -q "401" "$log_file"; then
        show_error_detail "auth" "$(grep "401" "$log_file" | head -1)"
        return $ERROR_AUTH
    elif grep -q "403" "$log_file"; then
        show_error_detail "permission" "$(grep "403" "$log_file" | head -1)"
        return $ERROR_PERMISSION
    elif grep -q "404" "$log_file"; then
        show_error_detail "index_not_found" "$(grep "404" "$log_file" | head -1)"
        return $ERROR_INDEX_NOT_FOUND
    elif grep -q "timeout" "$log_file"; then
        show_error_detail "timeout" "$(grep "timeout" "$log_file" | head -1)"
        return $ERROR_TIMEOUT
    else
        # 显示最后几行错误日志
        echo ""
        error "任务失败"
        echo ""
        echo "最后的错误日志:"
        tail -n 10 "$log_file" | sed 's/^/  /'
        echo ""
        return $ERROR_UNKNOWN
    fi
}

# 错误恢复建议
suggest_recovery() {
    local index_name="$1"
    local error_code="$2"
    
    echo ""
    echo "🔄 恢复建议:"
    echo ""
    
    case "$error_code" in
        $ERROR_CONNECTION|$ERROR_AUTH|$ERROR_PERMISSION)
            echo "  1. 修复连接或认证问题"
            echo "  2. 重新启动任务:"
            echo "     elasticdump-easy dump $index_name"
            ;;
            
        $ERROR_TIMEOUT)
            echo "  1. 使用更小的批量大小:"
            echo "     elasticdump-easy dump $index_name --limit=500"
            echo ""
            echo "  2. 或使用分片导出:"
            echo "     elasticdump-easy dump $index_name --shard=0"
            ;;
            
        $ERROR_INDEX_NOT_FOUND)
            echo "  1. 检查索引名是否正确"
            echo "  2. 列出所有可用索引"
            ;;
            
        *)
            echo "  1. 查看完整日志:"
            echo "     tail -f $(get_log_file "$index_name")"
            echo ""
            echo "  2. 使用 debug 模式重试:"
            echo "     elasticdump-easy dump $index_name --debug"
            ;;
    esac
    
    echo ""
}

# 检查并报告错误
check_and_report_error() {
    local index_name="$1"
    local log_file
    log_file=$(get_log_file "$index_name")
    
    if [ ! -f "$log_file" ]; then
        error "日志文件不存在"
        return 1
    fi
    
    # 分析错误
    analyze_log_error "$log_file"
    local error_code=$?
    
    # 提供恢复建议
    if [ $error_code -ne 0 ]; then
        suggest_recovery "$index_name" "$error_code"
    fi
    
    return $error_code
}
