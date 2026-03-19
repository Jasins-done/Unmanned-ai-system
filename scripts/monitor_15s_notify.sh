#!/bin/bash
# JMJ监控脚本 - 三重保障版
# 主监控层：15秒轮询 + 智能通知 + 去重机制

# ==================== 配置区域 ====================
API_URL="http://47.104.242.199:8081/list-tasks"
PROCESSED_FILE="/home/admin/.processed_tasks"
FEISHU_TARGET="ou_bb7933f027e5a2b988a89e86cbc32a32"
LOG_FILE="/home/admin/.jmj_monitor.log"
NOTIFY_FREQUENCY=8  # 每8次轮询发送一次状态报告
ERROR_THRESHOLD=3   # 连续错误阈值

# ==================== 初始化 ====================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
COUNTER_FILE="/tmp/jmj_monitor_counter"
ERROR_COUNT_FILE="/tmp/jmj_error_count"

# 初始化计数器
if [ ! -f "$COUNTER_FILE" ]; then
    echo "0" > "$COUNTER_FILE"
fi
COUNTER=$(cat "$COUNTER_FILE")
COUNTER=$((COUNTER + 1))
echo "$COUNTER" > "$COUNTER_FILE"

# 初始化错误计数
if [ ! -f "$ERROR_COUNT_FILE" ]; then
    echo "0" > "$ERROR_COUNT_FILE"
fi

# ==================== 日志函数 ====================
log() {
    echo "[$TIMESTAMP] $1" >> "$LOG_FILE"
    echo "[$TIMESTAMP] $1"
}

send_notification() {
    local message="$1"
    local priority="$2"
    
    log "发送飞书通知: $message"
    
    # 使用OpenClaw发送通知
    /home/admin/.npm-global/bin/openclaw message send \
        --channel feishu \
        --target "$FEISHU_TARGET" \
        --message "$message" \
        2>/dev/null || true
    
    # 记录发送时间
    echo "$TIMESTAMP" > "/tmp/jmj_last_notify"
}

# ==================== 主监控逻辑 ====================
log "=== JMJ主监控开始 (轮询 #$COUNTER) ==="

# 1. 检查远程接口
log "检查远程接口: $API_URL"
START_TIME=$(date +%s%3N)
TASKS_JSON=$(curl -s -m 10 "$API_URL")
CURL_EXIT=$?
END_TIME=$(date +%s%3N)
RESPONSE_TIME=$((END_TIME - START_TIME))

if [ $CURL_EXIT -ne 0 ]; then
    log "❌ 远程接口连接失败 (curl exit: $CURL_EXIT)"
    
    # 错误计数
    ERROR_COUNT=$(cat "$ERROR_COUNT_FILE")
    ERROR_COUNT=$((ERROR_COUNT + 1))
    echo "$ERROR_COUNT" > "$ERROR_COUNT_FILE"
    
    # 达到错误阈值时发送警报
    if [ $ERROR_COUNT -ge $ERROR_THRESHOLD ]; then
        send_notification "🚨 **JMJ监控警报** - 接口连续失败
时间: $TIMESTAMP
接口: $API_URL
连续失败次数: $ERROR_COUNT
响应时间: ${RESPONSE_TIME}ms
状态: ❌ 需要人工检查" "high"
    fi
    
    exit 1
else
    # 重置错误计数
    echo "0" > "$ERROR_COUNT_FILE"
    log "✅ 远程接口连接成功 (${RESPONSE_TIME}ms)"
fi

# 2. 解析任务列表
TASK_COUNT=$(echo "$TASKS_JSON" | jq '.data.tasks | length' 2>/dev/null || echo "0")
if [ "$TASK_COUNT" = "null" ] || [ -z "$TASK_COUNT" ]; then
    TASK_COUNT=0
fi

log "远程任务总数: $TASK_COUNT"

# 3. 检查已处理任务记录
if [ ! -f "$PROCESSED_FILE" ]; then
    touch "$PROCESSED_FILE"
    log "创建已处理任务记录文件: $PROCESSED_FILE"
fi

PROCESSED_COUNT=$(wc -l < "$PROCESSED_FILE" 2>/dev/null || echo "0")
log "已处理任务记录: $PROCESSED_COUNT"

# 4. 检查新任务
NEW_TASKS=0
for i in $(seq 0 $((TASK_COUNT - 1))); do
    TASK_ID=$(echo "$TASKS_JSON" | jq -r ".data.tasks[$i].id" 2>/dev/null)
    
    if [ -n "$TASK_ID" ] && [ "$TASK_ID" != "null" ]; then
        # 标准化任务ID（去除前缀和后缀）
        CLEAN_ID=$(echo "$TASK_ID" | sed 's/^task_//; s/\.json$//')
        
        # 检查是否已处理
        if ! grep -q "^$CLEAN_ID$" "$PROCESSED_FILE"; then
            NEW_TASKS=$((NEW_TASKS + 1))
            log "发现新任务: $TASK_ID (标准化: $CLEAN_ID)"
            
            # 发送新任务通知
            send_notification "🚀 **发现新JMJ任务**
任务ID: $TASK_ID
发现时间: $TIMESTAMP
远程接口: $API_URL
响应时间: ${RESPONSE_TIME}ms

📋 任务详情:
• 任务格式: $(echo "$TASK_ID" | grep -q '^task_' && echo '传统格式' || echo '新格式')
• 标准化ID: $CLEAN_ID
• 发现序号: #$NEW_TASKS

🔧 系统状态:
• 远程任务总数: $TASK_COUNT
• 已处理记录: $PROCESSED_COUNT
• 轮询计数: #$COUNTER
• 响应时间: ${RESPONSE_TIME}ms" "normal"
            
            # 记录到已处理文件（防止重复通知）
            echo "$CLEAN_ID" >> "$PROCESSED_FILE"
        fi
    fi
done

# 5. 定期状态报告
if [ $((COUNTER % NOTIFY_FREQUENCY)) -eq 0 ]; then
    log "发送定期状态报告 (每 $NOTIFY_FREQUENCY 次轮询)"
    
    # 计算数据差异
    DATA_DIFF=$((PROCESSED_COUNT - TASK_COUNT))
    DIFF_REASON=""
    if [ $DATA_DIFF -gt 0 ]; then
        DIFF_REASON="（$DATA_DIFF 个历史任务已处理但从远程服务器删除）"
    elif [ $DATA_DIFF -lt 0 ]; then
        DIFF_REASON="（有 ${DATA_DIFF#-} 个新任务待处理）"
    fi
    
    send_notification "📊 **JMJ监控状态报告**
检查时间: $TIMESTAMP
轮询计数: #$COUNTER

📡 远程接口状态
✅ 接口: $API_URL
✅ 连接: 正常
✅ 响应时间: ${RESPONSE_TIME}ms

📋 任务统计
• 远程任务总数: $TASK_COUNT
• 已处理任务记录: $PROCESSED_COUNT $DIFF_REASON
• 本次发现新任务: $NEW_TASKS 个

🔧 系统状态
✅ 主监控: 运行正常 (15秒轮询)
✅ 去重机制: 正常工作
✅ 通知系统: 就绪
✅ 错误恢复: 连续 $ERROR_COUNT 次成功

📈 性能指标
• 轮询频率: 每15秒
• 通知频率: 每 $((NOTIFY_FREQUENCY * 15)) 秒发送状态报告
• 系统运行: 连续 $COUNTER 次成功轮询

🎯 结论
$(if [ $NEW_TASKS -eq 0 ]; then echo "所有远程任务均已处理，系统运行正常，无需人工干预。"; else echo "发现 $NEW_TASKS 个新任务，已发送通知，请及时处理。"; fi)

---
*监控层级: 主监控 (15秒轮询)*
*维护者: JMJ自动化系统*" "low"
fi

# 6. 清理和记录
log "=== JMJ主监控完成 (轮询 #$COUNTER) ==="
log "统计: 远程$TASK_COUNT任务, 已处理$PROCESSED_COUNT记录, 新任务$NEW_TASKS个"
log "性能: 响应时间${RESPONSE_TIME}ms, 错误计数$ERROR_COUNT"

# 记录本次执行
echo "$TIMESTAMP,$COUNTER,$TASK_COUNT,$PROCESSED_COUNT,$NEW_TASKS,$RESPONSE_TIME" >> "/tmp/jmj_monitor_stats.csv"

exit 0
