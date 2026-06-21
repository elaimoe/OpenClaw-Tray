> ⚠️ **安全提示**：本项目的 PowerShell 和 VBScript 脚本可能会被部分杀毒软件误报为可疑程序，因为涉及后台进程管理、端口转发等操作。这属于误报，请自行审查脚本内容确认安全后再使用。

# OpenClaw Node 系统托盘启动器

## 系统要求

- **操作系统**：Windows 10 / Windows 11
- **运行环境**：PowerShell 5.1+（Windows 内置）
- **依赖工具**：
  - [OpenClaw CLI](https://github.com/openclaw) — 已安装并配置
  - `ssh` — Windows 自带的 OpenSSH 客户端（通常位于 `C:\Windows\System32\OpenSSH\ssh.exe`）
  - `netstat` — Windows 自带

> 本工具专为 Windows 设计，依赖 Windows 系统托盘（NotifyIcon）、.NET Process API、VBScript 等 Windows 专属组件，**不支持 Linux / macOS**。

## 作用

OpenClaw Node 需要通过 SSH 隧道连接远程网关才能运行，且进程管理比较繁琐（需要保持终端、异常退出会残留进程等）。本工具将整个启动和运维流程封装为一个系统托盘应用，开机自启、后台运行、自动保活，无需手动操作。

## 功能

- **系统托盘常驻** — 右键菜单一键重启或退出，状态一目了然
- **SSH 隧道自动管理** — 自动建立本地端口转发到远程 OpenClaw 网关
- **节点身份标识** — 支持 `--node-id` 和 `--display-name`，默认使用系统设备名
- **进程健康检查** — 每 N 秒检测 SSH 和 Node 进程状态，故障时自动重试恢复
- **日志落盘** — Node 的 stdout/stderr 写入日志文件，方便排查问题
- **单实例保护** — Mutex 互斥锁防止重复启动
- **孤儿进程清理** — 启动时自动清理上次异常退出残留的进程
- **无窗口运行** — 所有进程均在后台运行，不占用任务栏

## 快速开始

### 1. 准备配置

编辑 `openclaw-tray.ps1` 顶部的配置区，填入你自己的参数：

```powershell
$CheckIntervalSeconds = 10
$SshKey = "$env:USERPROFILE\.ssh\YOUR_KEY.pem"   # SSH 私钥路径
$RemoteHost = 'user@your-server.com'              # 远程服务器地址
$LocalPort = 18789                                 # 本地转发端口
$NodeId = $env:COMPUTERNAME                       # 节点 ID（默认用系统设备名）
$DisplayName = $env:COMPUTERNAME                  # 显示名称
$LogDir = "$env:USERPROFILE\.openclaw\tray-logs"  # 日志目录
$NodeLog = Join-Path $LogDir "node.log"           # Node 日志文件
```

### 2. 启动

**方式一：双击桌面快捷方式**

双击 `OpenClaw Node` 快捷方式即可启动，无任何窗口弹出。

**方式二：手动运行**

```powershell
powershell -ExecutionPolicy Bypass -File openclaw-tray.ps1
```

**方式三：通过 VBScript 启动（隐藏窗口）**

```powershell
cscript //nologo openclaw-tray.vbs
```

### 3. 使用托盘

启动后，系统托盘会出现 OpenClaw 图标：

- **绿色运行中** — 右键图标查看状态，显示 `Running` 即一切正常
- **需要重启** — 右键 → `Restart`，脚本会终止所有进程并重新启动
- **退出** — 右键 → `Exit`，彻底关闭所有相关进程

### 4. 托盘状态说明

| 状态 | 含义 |
|------|------|
| `Running` | SSH 和 Node 均正常运行 |
| `SSH reconnecting...` | SSH 断开，正在自动重试 |
| `Node reconnecting...` | Node 断开，正在自动重试 |
| `SSH + Node down (stopped)` | 重试后仍失败，需手动点击 Restart |

## 文件说明

| 文件 | 说明 |
|------|------|
| `openclaw-tray.ps1` | 主脚本（PowerShell） |
| `openclaw-tray.vbs` | VBScript 启动器（隐藏 PowerShell 窗口） |
| `openclaw.ico` | 托盘图标 |
| `OpenClaw Node.lnk` | 桌面快捷方式 |

## 工作流程

1. **启动** — 创建 Mutex → 清理端口上的孤儿进程 → 创建日志目录 → 启动 SSH 隧道 → 等待 2 秒 → 启动 Node（带 `--node-id` 和 `--display-name`，日志写入文件）
2. **健康检查** — 每 N 秒：通过 PID 检查 SSH 存活，通过 PID 检查 Node 进程存活
3. **自动重试** — 故障时自动重试一次；仍失败则显示 `stopped`，不再重试
4. **退出** — 终止所有进程 → 隐藏托盘图标 → 释放定时器 → 释放 Mutex → 退出

## 注意事项

- **Node 日志** — Node 的 stdout/stderr 通过 `*>` 重定向到 `$NodeLog`（默认 `~\.openclaw\tray-logs\node.log`），排查问题时查看此文件
- **节点身份** — `--node-id` 会覆盖默认节点 ID，节点首次连接时 Gateway 会产生配对请求，需批准后才能使用
- **UTF-8 无 BOM** — PowerShell 5.x 解析 `.ps1` 文件时要求无 BOM 的 UTF-8 编码，使用 `[System.IO.File]::WriteAllText()` 写入

## 许可证

MIT
