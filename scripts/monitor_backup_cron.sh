#!/bin/bash
# JMJ备用监控脚本 - cron独立会话版
# 备用监控层：独立会话，防止主监控失效

# ==================== 配置区域 ====================
API_URL="http://47.104.242.199:8081/list-tasks"
PROCESSED_FILE="/home/admin/.processed_tasks"
FEISHU_TARGET="ou_bb7933f027e5a2b988a89e86cbc32a32"
BACKUP_LOG="/tmp/jmj_backup_monitor.log"
UUID=$(cat /proc/sys/kernel/random/uuid | cut -d'-' -f1)

# ==================== 日志函数 ====================
log() {
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] [BACKUP-$UUID] $1" >> "$BACKUP_LOG"
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] [BACKUP-$UUID] $1"
}

send_notification() {
    local message="$1"
    
    log "发送备用监控通知"
    
    # 使用OpenClaw发送通知（独立会话）
    /home/admin/.npm-global/bin/openclaw message send \
        --channel feishu \
        --target "$FEISHU_TARGET" \
        --message "$message" \
        2>/dev/null || true
}

# ==================== 备用监控逻辑 ====================
log "=== JMJ备用监控开始 ==="

# 1. 检查主监控是否运行
MAIN_MONITOR_PID=$(ps aux | grep "monitor_15s_notify.sh" | grep -v grep | head -1 | awk '{print $2}')
if [ -n "$MAIN_MONITOR_PID" ]; then
    log "✅ 主监控运行正常 (PID: $MAIN_MONITOR_PID)"
    MAIN_STATUS="✅ 运行中"
else
    log "⚠️ 主监控未运行，备用监控接管"
    MAIN_STATUS="❌ 未运行"
    
    # 发送主监控异常通知
    send_notification "⚠️ **JMJ备用监控警报** - 主监控异常
时间: $(date "+%Y-%m-%d %H:%M:%S")
监控ID: BACKUP-$UUID

🔧 系统状态:
• 主监控状态: $MAIN_STATUS
• 备用监控: ✅ 已接管
• 监控频率: 每分钟检查一次

📋 处理措施:
1. 备用监控已自动接管
2. 继续执行任务检测
3. 发送本通知提醒

🎯 建议:
• 检查主监控脚本是否正常
• 查看日志文件: /home/admin/.jmj_monitor.log
• 如需重启主监控，运行: bash /opt/jmj-monitor-system-backup/scripts/start_all.sh

---
*监控层级: 备用监控 (cron独立会话)*
*紧急程度: 中等*"
fi

# 2. 检查远程接口
log "检查远程接口: $API_URL"
START_TIME=$(date +%s%3N)
TASKS_JSON=$(curl -s -m 15 "$API_URL")
CURL_EXIT=$?
END_TIME=$(date +%s%3N)
RESPONSE_TIME=$((END_TIME - START_TIME))

if [ $CURL_EXIT -ne 0 ]; then
    log "❌ 远程接口连接失败"
    
    send_notification "🚨 **JMJ备用监控严重错误** - 接口连接失败
时间: $(date "+%Y-%m-%d %H:%M:%S")
监控ID: BACKUP-$UUID

🔧 错误详情:
• 接口地址: $API_URL
• 错误代码: $CURL_EXIT
• 响应时间: ${RESPONSE_TIME}ms
• 主监控状态: $MAIN_STATUS

📋 可能原因:
1. 网络连接问题
2. 远程服务器宕机
3. 接口地址变更

🚨 紧急措施:
1. 备用监控将继续重试
2. 建议立即检查网络连接
3. 验证远程服务器状态

---
*监控层级: 备用监控 (cron独立会话)*
*紧急程度: 高*"
    
    exit 1
fi

log "✅ 远程接口连接成功 (${RESPONSE_TIME}ms)"

# 3. 解析任务列表
TASK_COUNT=$(echo "$TASKS_JSON" | jq '.data.tasks | length' 2>/dev/null || echo "0")
if [ "$TASK_COUNT" = "null" ] || [ -z "$TASK_COUNT" ]; then
    TASK_COUNT=0
fi

# 4. 检查已处理任务
if [ ! -f "$PROCESSED_FILE" ]; then
    PROCESSED_COUNT=0
else
    PROCESSED_COUNT=$(wc -l < "$PROCESSED_FILE" 2>/dev/null || echo "0")
fi

# 5. 检查新任务
NEW_TASKS=0
TASK_DETAILS=""
for i in $(seq 0 $((TASK_COUNT - 1))); do
    TASK_ID=$(echo "$TASKS_JSON" | jq -r ".data.tasks[$i].id" 2>/dev/null)
    
    if [ -n "$TASK_ID" ] && [ "$TASK_ID" != "null" ]; then
        CLEAN_ID=$(echo "$TASK_ID" | sed 's/^task_//; s/\.json$//')
        
        if ! grep -q "^$CLEAN_ID$" "$PROCESSED_FILE"; then
            NEW_TASKS=$((NEW_TASKS + 1))
            TASK_DETAILS="${TASK_DETAILS}• $TASK_ID\n"
            log "发现未处理任务: $TASK_ID"
        fi
    fi
done

# 6. 发送状态报告
if [ $NEW_TASKS -gt 0 ] || [ "$MAIN_STATUS" = "❌ 未运行" ]; then
    log "发送备用监控报告: 新任务$NEW_TASKS个, 主监控$MAIN_STATUS"
    
    REPORT_TITLE="📋 **JMJ备用监控报告**"
    if [ "$MAIN_STATUS" = "❌ 未运行" ]; then
        REPORT_TITLE="⚠️ **JMJ备用监控警报** - 主监控异常"
    elif [ $NEW_TASKS -gt 0 ]; then
        REPORT_TITLE="🚀 **JMJ备用监控发现新任务**"
    fi
    
    send_notification "$REPORT_TITLE
时间: $(date "+%Y-%m-%d %H:%M:%S")
监控ID: BACKUP-$UUID

🔧 系统状态:
• 主监控状态: $MAIN_STATUS
• 备用监控: ✅ 运行中
• 监控频率: 每分钟检查一次

📊 任务统计:
• 远程任务总数: $TASK_COUNT
• 已处理任务记录: $PROCESSED_COUNT
• 本次发现新任务: $NEW_TASKS 个

$(if [ $NEW_TASKS -gt 0 ]; then echo "📋 新任务列表:\n$TASK_DETAILS"; fi)

📈 性能指标:
• 接口响应时间: ${RESPONSE_TIME}ms
• 检查时间: $(date "+%H:%M:%S")
• 备用监控UUID: $UUID

🎯 结论:
$(if [ "$MAIN_STATUS" = "❌ 未运行" ]; then 
    echo "主监控异常，备用监控已接管，建议检查主监控状态。"
elif [ $NEW_TASKS -gt 0 ]; then 
    echo "发现 $NEW_TASKS 个新任务，请及时处理。"
else
    echo "系统运行正常，备用监控就绪。"
fi)

---
*监控层级: 备用监控 (cron独立会话)*
*报告频率: 异常时或发现新任务时*
*维护者: JMJ自动化系统*"
fi

# 7. 记录执行
log "=== JMJ备用监控完成 ==="
log "统计: 远程$TASK_COUNT任务, 已处理$PROCESSED_COUNT记录, 新任务$NEW_TASKS个"
log "状态: 主监控$MAIN_STATUS, 响应时间${RESPONSE_TIME}ms"

exit 0
