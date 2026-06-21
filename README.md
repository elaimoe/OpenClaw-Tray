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

OpenClaw Node 需要连接远程网关才能运行，但直接将端口暴露在公网上存在安全风险。通过 SSH 隧道端口转发，可以安全地将远程网关的流量转发到本地，无需对外开放端口。本工具将 SSH 隧道和 Node 进程的启动、保活、重启封装为一个系统托盘应用，开机自启、后台运行、自动恢复，无需手动操作。

## 功能

- **系统托盘常驻** — 右键菜单一键重启或退出，状态一目了然
- **SSH 隧道自动管理** — 自动建立本地端口转发到远程 OpenClaw 网关，带 keepalive 和端口绑定失败检测
- **节点身份标识** — `--node-id` 和 `--display-name` 默认使用系统设备名（`$env:COMPUTERNAME`），换机器自动适配
- **进程健康检查** — 每 N 秒检测 SSH 和 Node 进程状态，故障时带冷却时间自动重试
- **递归进程清理** — 深度优先杀进程树，Restart 和退出时彻底清理残留
- **端口清理** — 启动和 Restart 时自动清理占用转发端口的孤儿进程
- **单实例保护** — Mutex 互斥锁防止重复启动
- **无窗口运行** — 所有进程均在后台运行，不占用任务栏

## 快速开始

### 1. 安装

将本项目放到任意目录，推荐：

```
C:\Users\<你的用户名>\.openclaw\
├── openclaw-tray.ps1       # 主脚本
├── openclaw-tray.vbs       # VBScript 启动器（隐藏窗口）
├── openclaw.ico            # 托盘图标
└── OpenClaw Node.lnk       # 桌面快捷方式（可选）
```

### 2. 准备 SSH 密钥

将远程服务器的 SSH 私钥放到：

```
C:\Users\<你的用户名>\.ssh\<密钥文件>.pem
```

确保权限正确（仅当前用户可读）。如果没有密钥，可以在 Windows 上生成：

```powershell
ssh-keygen -t ed25519 -f "$env:USERPROFILE\.ssh\openclaw_key" -N ""
```

然后将公钥复制到远程服务器：

```powershell
scp "$env:USERPROFILE\.ssh\openclaw_key.pub" user@your-server:~/.ssh/authorized_keys
```

### 3. 编辑配置

打开 `openclaw-tray.ps1`，修改顶部配置区：

```powershell
# ======================== Config ============================
$CheckIntervalSeconds = 10                        # 健康检查间隔（秒）
$SshKey = "$env:USERPROFILE\.ssh\YOUR_KEY.pem"   # SSH 私钥路径
$RemoteHost = 'user@your-server.com'              # 远程服务器（user@host 格式）
$LocalPort = 18789                                 # 本地转发端口（需与远程 OpenClaw 网关端口一致）
$NodeName = $env:COMPUTERNAME                     # 节点名称（同时用作 --node-id 和 --display-name）
$RestartCooldownSeconds = 15                       # 自动重试冷却时间（秒）
# ============================================================
```

**配置说明：**

| 变量 | 说明 |
|------|------|
| `$CheckIntervalSeconds` | 多久检查一次 SSH 和 Node 进程是否存活，默认 10 秒 |
| `$SshKey` | SSH 私钥的完整路径，`$env:USERPROFILE` 会自动展开为 `C:\Users\<用户名>` |
| `$RemoteHost` | 远程服务器地址，格式为 `user@host`，脚本会通过 SSH 连接此服务器 |
| `$LocalPort` | 本地端口转发端口，SSH 会将远程服务器的此端口转发到本机 |
| `$NodeName` | 节点名称，默认使用系统设备名。OpenClaw 启动时会传入 `--node-id` 和 `--display-name` |
| `$RestartCooldownSeconds` | SSH 或 Node 故障后自动重试的最小间隔，防止频繁重启 |

### 4. 启动

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

**方式四：开机自启**

1. 按 `Win + R`，输入 `shell:startup`，回车打开启动文件夹
2. 将 `OpenClaw Node.lnk` 快捷方式复制到该文件夹
3. 或者在启动文件夹中创建新的快捷方式，目标指向：

```
wscript.exe "C:\Users\<你的用户名>\.openclaw\openclaw-tray.vbs"
```

### 5. 使用托盘

启动后，系统托盘会出现 OpenClaw 图标：

- **右键图标** → 查看状态、Restart、Exit
- **Restart** — 终止所有进程并重新启动（会重新加载 `openclaw.json` 配置）
- **Exit** — 彻底关闭所有相关进程并退出

### 6. 托盘状态说明

| 状态 | 含义 |
|------|------|
| `OpenClaw Node - Running` | SSH 和 Node 均正常运行 |
| `OpenClaw Node - SSH reconnecting...` | SSH 断开，正在自动重试 |
| `OpenClaw Node - Node reconnecting...` | Node 断开，正在自动重试 |
| `OpenClaw Node - SSH + Node down (stopped)` | 自动重试后仍失败，需手动点击 Restart |

## 文件说明

| 文件 | 说明 |
|------|------|
| `openclaw-tray.ps1` | 主脚本（PowerShell），所有逻辑都在这里 |
| `openclaw-tray.vbs` | VBScript 启动器，用于隐藏 PowerShell 窗口 |
| `openclaw.ico` | 托盘图标（766 bytes） |
| `OpenClaw Node.lnk` | 桌面快捷方式 |

## 路径说明

| 路径 | 说明 |
|------|------|
| `~\.openclaw\openclaw.json` | OpenClaw 配置文件，Restart 时会重新加载 |
| `~\.openclaw\openclaw-tray.ps1` | 托盘脚本（安装位置） |
| `~\.openclaw\openclaw-tray.vbs` | VBScript 启动器（安装位置） |
| `~\.openclaw\openclaw.ico` | 托盘图标（安装位置） |
| `~\.ssh\<密钥>.pem` | SSH 私钥 |
| `C:\Windows\System32\OpenSSH\ssh.exe` | Windows 自带 SSH 客户端 |

> `~` 代表 `$env:USERPROFILE`，通常是 `C:\Users\<你的用户名>`

## 工作流程

1. **启动** — 创建 Mutex → 清理端口上的孤儿进程 → 启动 SSH 隧道 → 等待 2 秒 → 启动 Node（带 `--node-id` 和 `--display-name`）
2. **健康检查** — 每 N 秒通过 PID 检查 SSH 和 Node 进程是否存活
3. **自动重试** — 故障时带冷却时间自动重试（默认 15 秒内不重复重试）；重试一次后仍失败则显示 `stopped`
4. **Restart** — 杀进程树（递归）→ 清理端口 → 重启 SSH 和 Node
5. **退出** — 杀进程树 → 隐藏托盘图标 → 释放定时器 → 释放 Mutex → 退出

## SSH 隧道参数

脚本启动 SSH 时使用以下参数：

```
ssh -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=30 \
    -o ServerAliveCountMax=3 \
    -i <密钥路径> \
    -N \
    -L 18789:127.0.0.1:18789 \
    <user@host>
```

| 参数 | 作用 |
|------|------|
| `ExitOnForwardFailure=yes` | 端口转发失败时 SSH 立即退出，避免假阳性 |
| `ServerAliveInterval=30` | 每 30 秒发送一次心跳，检测连接存活 |
| `ServerAliveCountMax=3` | 连续 3 次心跳无响应则断开 |
| `-N` | 不执行远程命令，仅做隧道 |
| `-L 18789:127.0.0.1:18789` | 本地转发：远程 127.0.0.1:18789 → 本机 127.0.0.1:18789 |

## 注意事项

- **节点身份** — `--node-id` 会覆盖默认节点 ID，节点首次连接时 Gateway 会产生配对请求，需批准后才能使用
- **Restart 与配置更新** — 修改 `openclaw.json` 后，点 Restart 即可生效（新进程会重新读取配置）
- **UTF-8 无 BOM** — PowerShell 5.x 解析 `.ps1` 文件时要求无 BOM 的 UTF-8 编码

## 许可证

MIT
