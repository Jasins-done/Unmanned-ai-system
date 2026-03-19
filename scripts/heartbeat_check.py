#!/usr/bin/env python3
"""
JMJ心跳检查脚本 - 系统级监控
功能: 检查OpenClaw服务状态，自动恢复，系统级监控
"""

import os
import sys
import json
import time
import subprocess
import logging
from datetime import datetime

# ==================== 配置区域 ====================
CONFIG = {
    "openclaw_check_interval": 300,  # 5分钟检查一次
    "max_retries": 3,
    "feishu_target": "ou_bb7933f027e5a2b988a89e86cbc32a32",
    "log_file": "/tmp/jmj_heartbeat.log",
    "status_file": "/tmp/jmj_system_status.json",
    "monitor_scripts": [
        "/opt/jmj-monitor-system-backup/scripts/monitor_15s_notify.sh",
        "/opt/jmj-monitor-system-backup/scripts/monitor_backup_cron.sh"
    ]
}

# ==================== 日志配置 ====================
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [HEARTBEAT] %(message)s',
    handlers=[
        logging.FileHandler(CONFIG["log_file"]),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# ==================== 工具函数 ====================
def send_feishu_notification(message, priority="normal"):
    """发送飞书通知"""
    try:
        cmd = [
            "/home/admin/.npm-global/bin/openclaw",
            "message", "send",
            "--channel", "feishu",
            "--target", CONFIG["feishu_target"],
            "--message", message
        ]
        
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        
        if result.returncode == 0:
            logger.info(f"飞书通知发送成功: {message[:50]}...")
            return True
        else:
            logger.error(f"飞书通知发送失败: {result.stderr}")
            return False
    except Exception as e:
        logger.error(f"发送飞书通知异常: {e}")
        return False

def check_openclaw_status():
    """检查OpenClaw服务状态"""
    try:
        cmd = ["/home/admin/.npm-global/bin/openclaw", "status"]
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
        
        if result.returncode == 0:
            # 解析状态输出
            status_lines = result.stdout.strip().split('\n')
            status_info = {}
            
            for line in status_lines:
                if ':' in line:
                    key, value = line.split(':', 1)
                    status_info[key.strip()] = value.strip()
            
            logger.info("OpenClaw服务状态正常")
            return {
                "status": "running",
                "details": status_info,
                "raw_output": result.stdout
            }
        else:
            logger.warning(f"OpenClaw状态检查失败: {result.stderr}")
            return {
                "status": "error",
                "error": result.stderr,
                "raw_output": result.stdout
            }
    except subprocess.TimeoutExpired:
        logger.error("OpenClaw状态检查超时")
        return {"status": "timeout", "error": "检查超时"}
    except Exception as e:
        logger.error(f"OpenClaw状态检查异常: {e}")
        return {"status": "exception", "error": str(e)}

def check_monitor_scripts():
    """检查监控脚本运行状态"""
    script_status = {}
    
    for script in CONFIG["monitor_scripts"]:
        script_name = os.path.basename(script)
        
        # 检查文件是否存在
        if not os.path.exists(script):
            script_status[script_name] = {"status": "missing", "path": script}
            continue
        
        # 检查进程是否运行
        try:
            # 查找相关进程
            cmd = f"ps aux | grep '{script_name}' | grep -v grep | wc -l"
            process_count = int(subprocess.check_output(cmd, shell=True).decode().strip())
            
            if process_count > 0:
                script_status[script_name] = {"status": "running", "count": process_count}
            else:
                script_status[script_name] = {"status": "stopped", "count": 0}
                
        except Exception as e:
            script_status[script_name] = {"status": "check_error", "error": str(e)}
    
    return script_status

def check_cron_service():
    """检查cron服务状态"""
    try:
        # 检查cron服务
        cmd = "systemctl is-active cron"
        cron_status = subprocess.check_output(cmd, shell=True).decode().strip()
        
        # 检查cron任务
        cmd = "crontab -l | grep -c jmj"
        cron_jobs = int(subprocess.check_output(cmd, shell=True).decode().strip())
        
        return {
            "service": cron_status,
            "jmj_jobs": cron_jobs,
            "status": "active" if cron_status == "active" else "inactive"
        }
    except subprocess.CalledProcessError as e:
        return {"service": "error", "error": str(e), "status": "error"}
    except Exception as e:
        return {"service": "exception", "error": str(e), "status": "exception"}

def restart_openclaw():
    """重启OpenClaw服务"""
    try:
        logger.info("尝试重启OpenClaw服务...")
        
        # 停止服务
        stop_cmd = ["pkill", "-f", "openclaw-gateway"]
        subprocess.run(stop_cmd, timeout=10)
        time.sleep(2)
        
        # 启动服务
        start_cmd = ["/home/admin/.npm-global/bin/openclaw", "gateway", "start"]
        result = subprocess.run(start_cmd, capture_output=True, text=True, timeout=30)
        
        if result.returncode == 0:
            logger.info("OpenClaw服务重启成功")
            return {"status": "restarted", "output": result.stdout}
        else:
            logger.error(f"OpenClaw服务重启失败: {result.stderr}")
            return {"status": "restart_failed", "error": result.stderr}
            
    except Exception as e:
        logger.error(f"重启OpenClaw服务异常: {e}")
        return {"status": "exception", "error": str(e)}

def save_system_status(status_data):
    """保存系统状态到文件"""
    try:
        status_data["last_check"] = datetime.now().isoformat()
        
        with open(CONFIG["status_file"], 'w') as f:
            json.dump(status_data, f, indent=2, ensure_ascii=False)
        
        logger.info(f"系统状态已保存: {CONFIG['status_file']}")
    except Exception as e:
        logger.error(f"保存系统状态失败: {e}")

# ==================== 主检查函数 ====================
def perform_heartbeat_check():
    """执行心跳检查"""
    logger.info("=" * 60)
    logger.info("开始JMJ系统心跳检查")
    logger.info("=" * 60)
    
    check_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    check_results = {
        "timestamp": check_time,
        "components": {},
        "overall_status": "healthy",
        "issues": [],
        "actions_taken": []
    }
    
    # 1. 检查OpenClaw服务
    logger.info("检查OpenClaw服务状态...")
    openclaw_status = check_openclaw_status()
    check_results["components"]["openclaw"] = openclaw_status
    
    if openclaw_status["status"] != "running":
        check_results["overall_status"] = "degraded"
        check_results["issues"].append(f"OpenClaw服务异常: {openclaw_status.get('status', 'unknown')}")
        
        # 尝试自动恢复
        logger.warning("OpenClaw服务异常，尝试自动恢复...")
        restart_result = restart_openclaw()
        check_results["actions_taken"].append({
            "action": "restart_openclaw",
            "result": restart_result
        })
        
        # 发送警报通知
        alert_message = f"""🚨 **JMJ系统心跳警报** - OpenClaw服务异常
检查时间: {check_time}

🔧 异常详情:
• 服务状态: {openclaw_status.get('status', 'unknown')}
• 错误信息: {openclaw_status.get('error', '无')}

🛠️ 自动恢复:
• 恢复操作: 自动重启OpenClaw服务
• 恢复结果: {restart_result.get('status', 'unknown')}
• 恢复时间: {datetime.now().strftime('%H:%M:%S')}

📋 建议措施:
1. 检查OpenClaw日志: /home/admin/.openclaw/logs/
2. 验证服务配置
3. 监控后续状态

---
*监控层级: 系统心跳检查 (5分钟)*
*紧急程度: 高*"""
        
        send_feishu_notification(alert_message, "high")
    
    # 2. 检查监控脚本
    logger.info("检查监控脚本状态...")
    monitor_status = check_monitor_scripts()
    check_results["components"]["monitor_scripts"] = monitor_status
    
    for script_name, status_info in monitor_status.items():
        if status_info.get("status") != "running":
            check_results["issues"].append(f"监控脚本异常: {script_name} - {status_info.get('status')}")
            
            if status_info.get("status") == "stopped":
                # 尝试启动监控脚本
                try:
                    script_path = f"/opt/jmj-monitor-system-backup/scripts/{script_name}"
                    if os.path.exists(script_path):
                        subprocess.Popen(["bash", script_path], 
                                       stdout=subprocess.DEVNULL, 
                                       stderr=subprocess.DEVNULL)
                        logger.info(f"已启动监控脚本: {script_name}")
                        check_results["actions_taken"].append({
                            "action": f"start_script_{script_name}",
                            "result": "started"
                        })
                except Exception as e:
                    logger.error(f"启动监控脚本失败: {script_name} - {e}")
    
    # 3. 检查cron服务
    logger.info("检查cron服务状态...")
    cron_status = check_cron_service()
    check_results["components"]["cron_service"] = cron_status
    
    if cron_status.get("status") != "active":
        check_results["overall_status"] = "degraded"
        check_results["issues"].append(f"cron服务异常: {cron_status.get('status')}")
        
        # 尝试重启cron服务
        try:
            subprocess.run(["sudo", "systemctl", "restart", "cron"], timeout=10)
            logger.info("已重启cron服务")
            check_results["actions_taken"].append({
                "action": "restart_cron",
                "result": "restarted"
            })
        except Exception as e:
            logger.error(f"重启cron服务失败: {e}")
    
    # 4. 检查cron任务数量
    if cron_status.get("jmj_jobs", 0) < 4:  # 应该有4个JMJ cron任务
        check_results["issues"].append(f"JMJ cron任务数量不足: {cron_status.get('jmj_jobs', 0)}/4")
    
    # 5. 生成状态报告
    logger.info("生成系统状态报告...")
    
    # 计算统计信息
    total_issues = len(check_results["issues"])
    total_actions = len(check_results["actions_taken"])
    
    # 发送定期状态报告（每6次检查发送一次）
    heartbeat_counter_file = "/tmp/jmj_heartbeat_counter"
    try:
        with open(heartbeat_counter_file, 'r') as f:
            counter = int(f.read().strip())
    except:
        counter = 0
    
    counter += 1
    with open(heartbeat_counter_file, 'w') as f:
        f.write(str(counter))
    
    if counter % 6 == 0 or check_results["overall_status"] != "healthy":
        # 发送详细状态报告
        status_emoji = "✅" if check_results["overall_status"] == "healthy" else "⚠️" if check_results["overall_status"] == "degraded" else "🚨"
        
        status_message = f"""{status_emoji} **JMJ系统心跳状态报告**
检查时间: {check_time}
检查次数: #{counter}

📊 系统概览:
• 整体状态: {check_results["overall_status"].upper()}
• 发现问题: {total_issues} 个
• 执行操作: {total_actions} 个

🔧 组件状态:
• OpenClaw服务: {openclaw_status.get('status', 'unknown').upper()}
• 监控脚本: {sum(1 for s in monitor_status.values() if s.get('status') == 'running')}/{len(monitor_status)} 运行中
• Cron服务: {cron_status.get('status', 'unknown').upper()}
• Cron任务: {cron_status.get('jmj_jobs', 0)} 个JMJ任务

📋 问题列表:
{chr(10).join(f'• {issue}' for issue in check_results['issues']) if check_results['issues'] else '• 无问题'}

🛠️ 执行操作:
{chr(10).join(f'• {action["action"]}: {action.get("result", "unknown")}' for action in check_results['actions_taken']) if check_results['actions_taken'] else '• 无操作'}

🎯 结论:
系统{(check_results['overall_status'] == 'healthy') and '运行正常' or '存在异常，已尝试自动恢复'}。

---
*监控层级: 系统心跳检查 (5分钟)*
*报告频率: 每30分钟或异常时*
*维护者: JMJ自动化系统*"""
        
        send_feishu_notification(status_message, "normal" if check_results["overall_status"] == "healthy" else "high")
    
    # 6. 保存系统状态
    save_system_status(check_results)
    
    logger.info("=" * 60)
    logger.info(f"心跳检查完成: 状态={check_results['overall_status']}, 问题={total_issues}, 操作={total_actions}")
    logger.info("=" * 60)
    
    return check_results

# ==================== 主程序 ====================
if __name__ == "__main__":
    try:
        # 设置工作目录
        os.chdir(os.path.dirname(os.path.abspath(__file__)))
        
        # 执行心跳检查
        results = perform_heartbeat_check()
        
        # 根据检查结果退出
        if results["overall_status"] == "healthy":
            sys.exit(0)
        else:
            sys.exit(1)
            
    except KeyboardInterrupt:
        logger.info("心跳检查被用户中断")
        sys.exit(0)
    except Exception as e:
        logger.error(f"心跳检查主程序异常: {e}")
        
        # 发送异常通知
        error_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        error_message = f"""🚨 **JMJ系统心跳检查异常**
时间: {error_time}

🔧 异常详情:
• 异常类型: {type(e).__name__}
• 错误信息: {str(e)}
• 检查脚本: {__file__}

📋 建议措施:
1. 检查心跳检查脚本日志
2. 验证Python环境
3. 检查系统资源

---
*监控层级: 系统心跳检查*
*紧急程度: 高*"""
        
        send_feishu_notification(error_message, "high")
        sys.exit(2)
