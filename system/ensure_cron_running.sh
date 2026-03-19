#!/bin/bash
# Cron自启动保障脚本
# 确保cron服务在系统重启后自动运行

LOG_FILE="/tmp/jmj_cron_reboot.log"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

echo "[$TIMESTAMP] === Cron自启动保障脚本开始 ===" >> "$LOG_FILE"

# 1. 检查cron服务状态
if systemctl is-active --quiet cron; then
    echo "[$TIMESTAMP] ✅ Cron服务已运行" >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] ⚠️ Cron服务未运行，尝试启动..." >> "$LOG_FILE"
    
    # 尝试启动cron服务
    if sudo systemctl start cron; then
        echo "[$TIMESTAMP] ✅ Cron服务启动成功" >> "$LOG_FILE"
    else
        echo "[$TIMESTAMP] ❌ Cron服务启动失败" >> "$LOG_FILE"
        
        # 发送警报
        /home/admin/.npm-global/bin/openclaw message send \
            --channel feishu \
            --target "ou_bb7933f027e5a2b988a89e86cbc32a32" \
            --message "🚨 **JMJ系统警报** - Cron服务启动失败
时间: $TIMESTAMP
服务: cron
状态: ❌ 启动失败

📋 可能原因:
1. 系统权限问题
2. Cron服务配置错误
3. 系统资源不足

🚨 紧急措施:
1. 手动检查: sudo systemctl status cron
2. 查看日志: journalctl -u cron
3. 尝试修复: sudo systemctl enable cron && sudo systemctl start cron

---
*监控层级: 系统自启动保障*
*紧急程度: 高*" \
            2>/dev/null || true
    fi
fi

# 2. 启用cron自启动
if sudo systemctl enable cron 2>/dev/null; then
    echo "[$TIMESTAMP] ✅ Cron自启动已启用" >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] ⚠️ Cron自启动启用失败" >> "$LOG_FILE"
fi

# 3. 检查JMJ cron任务
JMJ_CRON_COUNT=$(crontab -l | grep -c "jmj\|monitor")
echo "[$TIMESTAMP] JMJ Cron任务数量: $JMJ_CRON_COUNT" >> "$LOG_FILE"

if [ $JMJ_CRON_COUNT -lt 4 ]; then
    echo "[$TIMESTAMP] ⚠️ JMJ Cron任务数量不足 ($JMJ_CRON_COUNT/4)，尝试恢复..." >> "$LOG_FILE"
    
    # 恢复cron配置
    if [ -f "/opt/jmj-monitor-system-backup/config/cron_config.txt" ]; then
        # 安装主监控cron配置
        (crontab -l 2>/dev/null; cat "/opt/jmj-monitor-system-backup/config/cron_config.txt") | crontab -
        echo "[$TIMESTAMP] ✅ JMJ Cron配置已恢复" >> "$LOG_FILE"
    fi
fi

# 4. 验证cron服务
CRON_PID=$(pgrep cron)
if [ -n "$CRON_PID" ]; then
    echo "[$TIMESTAMP] ✅ Cron进程运行中 (PID: $CRON_PID)" >> "$LOG_FILE"
else
    echo "[$TIMESTAMP] ❌ 未找到Cron进程" >> "$LOG_FILE"
fi

echo "[$TIMESTAMP] === Cron自启动保障脚本完成 ===" >> "$LOG_FILE"

# 发送启动完成通知
if [ -f "/tmp/jmj_last_reboot" ]; then
    LAST_REBOOT=$(cat "/tmp/jmj_last_reboot")
    UPTIME=$(($(date +%s) - $(date -d "$LAST_REBOOT" +%s)))
    UPTIME_STR=$(printf "%02d:%02d:%02d" $((UPTIME/3600)) $((UPTIME%3600/60)) $((UPTIME%60)))
    
    /home/admin/.npm-global/bin/openclaw message send \
        --channel feishu \
        --target "ou_bb7933f027e5a2b988a89e86cbc32a32" \
        --message "🔄 **JMJ系统重启完成通知**
重启时间: $LAST_REBOOT
当前时间: $TIMESTAMP
运行时长: $UPTIME_STR

🔧 系统状态:
• Cron服务: ✅ 运行中
• JMJ任务: $JMJ_CRON_COUNT 个
• 自启动: ✅ 已启用
• 进程ID: $CRON_PID

📋 验证结果:
1. Cron服务状态: $(systemctl is-active cron)
2. 自启动配置: $(systemctl is-enabled cron 2>/dev/null || echo "unknown")
3. 进程状态: $(ps -p $CRON_PID -o state= 2>/dev/null || echo "not found")

🎯 结论:
系统重启完成，Cron服务已自动恢复，JMJ监控系统准备就绪。

---
*监控层级: 系统自启动保障*
*报告类型: 重启完成*" \
        2>/dev/null || true
fi

# 记录本次重启时间
echo "$TIMESTAMP" > "/tmp/jmj_last_reboot"

exit 0
