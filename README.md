# JMJ Unattended Multi-AI Collaborative Monitoring System - Triple Guarantee Full Backup Package

**JMJ 无人值守多AI协同监控系统 - 三重保障完整备份包**

📦 System Overview
This is a complete backup of the JMJ task monitoring system with a triple guarantee mechanism to ensure high availability and stability.

这是一套完整的 JMJ 任务监控系统备份，内置三重保障机制，确保系统 7×24 小时稳定运行、不中断、不漏报。

---

🏗️ System Architecture 系统架构

1. Primary Monitor (主监控层)
• Polling interval: 15 seconds
• Function: Real-time task detection + Feishu notification
• Feature: Automatic deduplication to avoid repeated processing

2. Backup Monitor (备用监控层)
• Execution interval: 1 minute (independent cron session)
• Function: Standalone monitoring to prevent main monitor failure
• Feature: Isolated process, not affected by the main session

3. Heartbeat Check (心跳检查层)
• Check interval: 5 minutes
• Function: Monitor OpenClaw service status + automatic recovery
• Feature: System-level monitoring for full-stack stability

---

📁 File Structure 文件结构

jmj-monitor-system-backup/
├── README.md               # Project description
├── INSTALL.md              # Installation guide
├── config/                 # Configuration files
├── scripts/                # Core monitoring scripts
├── system/                 # System service & auto-restart
├── logs/                   # Log directory
└── test/                   # Test scripts

---

🔧 Installation 安装步骤
1. Copy the entire directory to the target server
2. Follow commands in INSTALL.md
3. Configure Feishu ID and remote URL
4. Start the monitoring system

---

📊 Monitoring Indicators 监控指标
• Real-time performance: 15s delay
• Reliability: Triple guarantee, 99.9% uptime
• Scalability: Multi-server deployment supported
• Maintainability: Full logs + status reporting

---

🚀 Quick Start 快速启动
# Install cron tasks
sudo cp config/cron_config.txt /etc/cron.d/jmj-monitor

# Start all monitors
bash scripts/start_all.sh

# Check running status
bash scripts/check_status.sh

---

📞 Support 支持
• Logs: Check logs/ directory
• Real-time alerts: Feishu push
• Auto-recovery: Built-in restart mechanism

---

📌 IMPORTANT NOTICE 重要说明
This project is the **unattended basic framework** of the MJ Multi-AI Collaborative Monitoring System.

It is currently in the **TEST STAGE**.
The official API interface has NOT been developed yet.

Please wait for the official version update.
Thank you for your attention and patience!

---

Backup Time: 2026-03-19
Version: v1.0.0
