# INSTALL.md 

```markdown
# JMJ Monitor System Installation Guide

## 📋 Prerequisites
- Linux server (Ubuntu/CentOS)
- curl
- cron service
- OpenClaw installed and configured

---

## ⚠️ Important Notes for Current Version
- This system is currently in the **testing phase (Beta)**.
- This version is **only adapted for Feishu (Lark)** notifications and is being tested within Feishu.
- The universal IM temporary communication interface **has not been developed yet** and will be added in future updates.
- Interfaces and protocols are still being optimized. Please wait for the official release.

---

## 🚀 Quick Installation

### Step 1: Copy Files
```bash
# Copy the entire monitor system to the server
sudo cp -r jmj-monitor-system-backup /opt/
cd /opt/jmj-monitor-system-backup
```

### Step 2: Configure Parameters
```bash
# Edit configuration file
nano config/feishu_config.sample

# Modify these parameters:
FEISHU_TARGET="ou_bb7933f027e5a2b988a89e86cbc32a32"  # Your Feishu user ID
API_URL="http://47.104.242.199:8081/list-tasks"      # Remote task API
```

### Step 3: Install cron Configuration
```bash
# Install main monitor (15s polling)
sudo cp config/cron_config.txt /etc/cron.d/jmj-monitor

# Install backup monitor (independent session)
(crontab -l 2>/dev/null; echo "* * * * * cd /opt/jmj-monitor-system-backup && bash scripts/monitor_backup_cron.sh >> /tmp/jmj_backup_monitor.log 2>&1") | crontab -

# Install heartbeat check
(crontab -l 2>/dev/null; echo "*/5 * * * * cd /opt/jmj-monitor-system-backup && python3 scripts/heartbeat_check.py >> /tmp/jmj_heartbeat.log 2>&1") | crontab -
```

### Step 4: Initialize System
```bash
# Create log directory
mkdir -p logs

# Create processed tasks record file
cp config/processed_tasks.sample ~/.processed_tasks

# Set permissions
chmod +x scripts/*.sh
chmod +x system/*.sh
```

### Step 5: Start Monitoring
```bash
# Start all monitoring components
bash scripts/start_all.sh

# Verify status
bash scripts/check_status.sh
```

---

## 🔧 Detailed Configuration

### 1. Main Monitor (15s polling)
```bash
# Config file: scripts/monitor_15s_notify.sh
API_URL="http://47.104.242.199:8081/list-tasks"
PROCESSED_FILE="/home/admin/.processed_tasks"
FEISHU_TARGET="ou_bb7933f027e5a2b988a89e86cbc32a32"
NOTIFY_FREQUENCY=8
```

### 2. Backup Monitor (cron independent session)
```bash
# Config file: scripts/monitor_backup_cron.sh
# Runs every minute, isolated from main process
```

### 3. Heartbeat Check
```bash
# Config file: scripts/heartbeat_check.py
# Monitors OpenClaw status and auto-restarts on failure
```

---

## 🧪 Testing & Verification

### Test 1: Monitor Function
```bash
bash test/test_monitor.sh
```
Expected:
- Remote API connection OK
- Task parsing OK
- Deduplication working

### Test 2: Notification
```bash
bash test/test_notify.sh
```
Expected:
- Feishu notification sent successfully

### Test 3: System Status
```bash
bash scripts/check_status.sh
```
Expected:
- All monitors running
- cron active
- Heartbeat online

---

## 🛠️ Maintenance Commands

### Start / Stop / Restart
```bash
bash scripts/start_all.sh
bash scripts/stop_all.sh
bash scripts/restart_all.sh
```

### View Logs
```bash
tail -f logs/monitor_15s.log
tail -f /tmp/jmj_backup_monitor.log
tail -f /tmp/jmj_heartbeat.log
```

### Status Check
```bash
ps aux | grep -E "(monitor|jmj)" | grep -v grep
crontab -l | grep jmj
```

---

## 🔍 Troubleshooting

### Monitor not running
```bash
sudo systemctl status cron
crontab -l
bash scripts/monitor_15s_notify.sh
```

### Notification failed
```bash
openclaw status
openclaw message send --channel feishu --target "ou_bb7933f027e5a2b988a89e86cbc32a32" --message "Test"
```

### API connection failed
```bash
curl -s "http://47.104.242.199:8081/list-tasks" | head -5
ping -c 3 47.104.242.199
```

---

## 📈 Monitoring Metrics
- Response time: < 200ms
- Success rate: > 99.9%
- Task detection delay: < 15s
- Auto-recovery time: < 1 minute

---

## 📌 Version & Roadmap
- Current version: v1.0.0 (Testing)
- Supported: Feishu (Lark) notifications
- Coming soon: Universal IM interface, multi-platform support, web dashboard

---

## 📞 Support
For issues, check logs or contact the maintainer.

---
**Installed at**: $(date)
**Version**: v1.0.0 (Testing)
