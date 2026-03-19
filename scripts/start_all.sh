#!/bin/bash
# JMJ监控系统 - 一键启动脚本

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEM_DIR="$SCRIPT_DIR/../system"
CONFIG_DIR="$SCRIPT_DIR/../config"
LOG_DIR="$SCRIPT_DIR/../logs"
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

echo "=========================================="
echo "JMJ监控系统 - 一键启动"
echo "启动时间: $TIMESTAMP"
echo "=========================================="

# 1. 检查前置条件
echo "[1/6] 检查前置条件..."
if ! command -v curl &> /dev/null; then
    echo "❌ curl未安装，请先安装: sudo apt install curl"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "❌ jq未安装，请先安装: sudo apt install jq"
    exit 1
fi

if ! command -v /home/admin/.npm-global/bin/openclaw &> /dev/null; then
    echo "❌ OpenClaw未安装或路径不正确"
    exit 1
fi

echo "✅ 前置条件检查通过"

# 2. 创建日志目录
echo "[2/6] 创建日志目录..."
mkdir -p "$LOG_DIR"
mkdir -p /tmp/jmj_logs
echo "✅ 日志目录创建完成"

# 3. 设置脚本权限
echo "[3/6] 设置脚本权限..."
chmod +x "$SCRIPT_DIR"/*.sh
chmod +x "$SYSTEM_DIR"/*.sh
echo "✅ 脚本权限设置完成"

# 4. 安装cron配置
echo "[4/6] 安装cron配置..."
if [ -f "$CONFIG_DIR/cron_config.txt" ]; then
    # 备份现有cron配置
    crontab -l > "$LOG_DIR/cron_backup_$TIMESTAMP.txt" 2>/dev/null || true
    
    # 安装新的cron配置
    (crontab -l 2>/dev/null; cat "$CONFIG_DIR/cron_config.txt") | crontab -
    echo "✅ Cron配置安装完成"
else
    echo "⚠️ 未找到cron配置文件: $CONFIG_DIR/cron_config.txt"
fi

# 5. 启动系统保障脚本
echo "[5/6] 启动系统保障脚本..."
bash "$SYSTEM_DIR/ensure_cron_running.sh" &
echo "✅ 系统保障脚本已启动"

# 6. 验证启动结果
echo "[6/6] 验证启动结果..."
sleep 2

echo ""
echo "📊 启动验证结果:"
echo "------------------------------------------"

# 检查cron服务
if systemctl is-active --quiet cron; then
    echo "✅ Cron服务: 运行中"
else
    echo "❌ Cron服务: 未运行"
fi

# 检查cron任务
CRON_COUNT=$(crontab -l | grep -c "jmj\|monitor")
echo "📋 JMJ Cron任务: $CRON_COUNT 个"

# 检查监控进程
MONITOR_PIDS=$(ps aux | grep "monitor_15s_notify.sh" | grep -v grep | wc -l)
echo "🔧 监控进程: $MONITOR_PIDS 个运行中"

# 检查OpenClaw
if /home/admin/.npm-global/bin/openclaw status &> /dev/null; then
    echo "🚀 OpenClaw: 运行正常"
else
    echo "⚠️ OpenClaw: 状态异常"
fi

echo "------------------------------------------"

# 发送启动完成通知
/home/admin/.npm-global/bin/openclaw message send \
    --channel feishu \
    --target "ou_bb7933f027e5a2b988a89e86cbc32a32" \
    --message "🚀 **JMJ监控系统启动完成**
启动时间: $TIMESTAMP

📊 启动结果:
• Cron服务: $(systemctl is-active cron && echo '✅ 运行中' || echo '❌ 未运行')
• JMJ任务: $CRON_COUNT 个
• 监控进程: $MONITOR_PIDS 个运行中
• OpenClaw: $(/home/admin/.npm-global/bin/openclaw status &> /dev/null && echo '✅ 运行正常' || echo '⚠️ 状态异常')

🔧 系统配置:
• 监控频率: 15秒轮询
• 通知频率: 每2分钟状态报告
• 保障机制: 三重保障（主监控 + 备用监控 + 心跳检查）

🎯 启动状态: ✅ 完成
系统已启动并运行，开始监控JMJ任务。

---
*启动时间: $TIMESTAMP*
*系统版本: v1.0.0*" \
    2>/dev/null || echo "⚠️ 飞书通知发送失败"

echo ""
echo "=========================================="
echo "✅ JMJ监控系统启动完成"
echo "启动时间: $TIMESTAMP"
echo "监控频率: 15秒轮询"
echo "保障机制: 三重保障"
echo "=========================================="

exit 0
