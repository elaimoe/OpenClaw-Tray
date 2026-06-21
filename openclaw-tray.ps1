# ============================================================
#  OpenClaw Node - System Tray Launcher
# ============================================================

# ======================== Config ============================
$CheckIntervalSeconds = 10
$SshKey = "$env:USERPROFILE\.ssh\SSHBJ.pem"
$RemoteHost = 'ubuntu@elaina.cn'
$LocalPort = 18789
$NodeId = $env:COMPUTERNAME
$DisplayName = $env:COMPUTERNAME
$LogDir = "$env:USERPROFILE\.openclaw\tray-logs"
$NodeLog = Join-Path $LogDir "node.log"
$SshLog = Join-Path $LogDir "ssh.log"
$ConfigValidateLog = Join-Path $LogDir "config-validate.log"
$RestartCooldownSeconds = 15
# ============================================================

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$mutex = New-Object System.Threading.Mutex($false, 'Global\OpenClawTrayMutex')
if (!$mutex.WaitOne(0)) { exit }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ======================== Helpers ============================

function Stop-PortListeners {
    $portListeners = netstat -ano | Select-String "${LocalPort}.*LISTENING"
    foreach ($line in $portListeners) {
        $p = ($line -split '\s+')[-1]
        if ($p -and $p -ne '0' -and $p -ne $PID) {
            Stop-Process -Id ([int]$p) -Force -EA SilentlyContinue
        }
    }
}

# Recursively kill a process tree by PID
function Stop-ProcessTree($pid) {
    if ($pid -le 0) { return }
    # Kill children first (depth-first)
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$pid" -EA SilentlyContinue |
        ForEach-Object { Stop-ProcessTree $_.ProcessId }
    Stop-Process -Id $pid -Force -EA SilentlyContinue
}

function Validate-Config {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'openclaw.exe'
    $psi.Arguments = 'config validate'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdout = $proc.StandardOutput.ReadToEnd()
    $stderr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    $output = "$stdout`n$stderr"
    [System.IO.File]::WriteAllText($ConfigValidateLog, $output, [System.Text.UTF8Encoding]::new($false))
    return $proc.ExitCode -eq 0
}

# ======================== Process Mgmt ========================

# Clean up orphan listeners at startup
Stop-PortListeners
Start-Sleep 1

$global:SshPid = 0
$global:NodePid = 0
$global:Status = 'starting'
$global:SshRetried = $false
$global:NodeRetried = $false
$global:LastRestartAt = [datetime]::MinValue

function Stop-AllProcesses {
    if ($global:SshPid -gt 0) { Stop-ProcessTree $global:SshPid }
    if ($global:NodePid -gt 0) { Stop-ProcessTree $global:NodePid }
    # Fallback: kill any remaining node processes matching openclaw
    Get-Process node -EA SilentlyContinue | ForEach-Object {
        $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)" -EA SilentlyContinue).CommandLine
        if ($cmd -match 'openclaw') { Stop-ProcessTree $_.Id }
    }
}

function Test-SshAlive {
    if ($global:SshPid -le 0) { return $false }
    return [bool](Get-Process -Id $global:SshPid -EA SilentlyContinue)
}

function Test-NodeAlive {
    if ($global:NodePid -le 0) { return $false }
    return [bool](Get-Process -Id $global:NodePid -EA SilentlyContinue)
}

function Start-SshTunnel {
    $sshArgs = @(
        '-o', 'ExitOnForwardFailure=yes',
        '-o', 'ServerAliveInterval=30',
        '-o', 'ServerAliveCountMax=3',
        '-i', $SshKey,
        '-N',
        '-L', "${LocalPort}:127.0.0.1:${LocalPort}",
        $RemoteHost
    )
    $p = Start-Process ssh -ArgumentList $sshArgs -WindowStyle Hidden -PassThru -EA SilentlyContinue
    if ($p) { $global:SshPid = $p.Id }
}

function Start-OpenClawNode {
    # Validate config before starting node
    $configOk = Validate-Config
    if (!$configOk) {
        $global:NodeRetried = $true
        $global:Status = 'config-error'
        Set-TrayText 'OpenClaw Node - Config invalid'
        $notifyIcon.ShowBalloonTip(5000, 'OpenClaw', "Config validation failed. See:`n$ConfigValidateLog", 2)
        return
    }
    # Run openclaw node with explicit --node-id and --display-name.
    # Logs are written to $NodeLog for debugging.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"openclaw node run --host 127.0.0.1 --port $LocalPort --node-id $NodeId --display-name $DisplayName *> '$NodeLog'`""
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    if ($proc) { $global:NodePid = $proc.Id }
}

function Set-TrayText($text) {
    $statusItem.Text = $text
    $notifyIcon.Text = $text.Substring(0, [Math]::Min(63, $text.Length))
}

function Update-TrayStatus {
    $sshOk = Test-SshAlive
    $nodeOk = Test-NodeAlive

    if ($sshOk -and $nodeOk) {
        $global:SshRetried = $false
        $global:NodeRetried = $false
        if ($global:Status -eq 'starting') {
            $global:Status = 'running'
            Set-TrayText 'OpenClaw Node - Running'
        } elseif ($global:Status -ne 'running') {
            $global:Status = 'running'
            Set-TrayText 'OpenClaw Node - Running'
            $notifyIcon.ShowBalloonTip(2000, 'OpenClaw', 'Reconnected.', 1)
        }
        return
    }

    $parts = @()
    if (!$sshOk) { $parts += 'SSH' }
    if (!$nodeOk) { $parts += 'Node' }
    $downNames = $parts -join ' + '

    $now = [datetime]::Now
    $sinceLastRestart = ($now - $global:LastRestartAt).TotalSeconds

    if (!$sshOk -and $sinceLastRestart -ge $RestartCooldownSeconds) {
        $global:SshRetried = $true
        $global:LastRestartAt = $now
        Stop-PortListeners
        Start-SshTunnel
        $notifyIcon.ShowBalloonTip(3000, 'OpenClaw', 'SSH down, retrying...', 2)
    }
    if (!$nodeOk -and $sinceLastRestart -ge $RestartCooldownSeconds) {
        $global:NodeRetried = $true
        $global:LastRestartAt = $now
        Start-OpenClawNode
        $notifyIcon.ShowBalloonTip(3000, 'OpenClaw', 'Node down, retrying...', 2)
    }

    $sshFailed = !$sshOk -and $global:SshRetried
    $nodeFailed = !$nodeOk -and $global:NodeRetried
    if ($sshFailed -or $nodeFailed) {
        $global:Status = 'failed'
        Set-TrayText "OpenClaw Node - $downNames down (stopped)"
    } else {
        $global:Status = 'disconnected'
        Set-TrayText "OpenClaw Node - $downNames reconnecting..."
    }
}

# ======================== Startup ============================

Start-SshTunnel
Start-Sleep 2
Start-OpenClawNode

$notifyIcon = New-Object System.Windows.Forms.NotifyIcon
$icoPath = Join-Path $PSScriptRoot 'openclaw.ico'
if (Test-Path $icoPath) {
    $notifyIcon.Icon = New-Object System.Drawing.Icon($icoPath)
} else {
    $notifyIcon.Icon = [System.Drawing.SystemIcons]::Application
}
$notifyIcon.Text = 'OpenClaw Node'
$notifyIcon.Visible = $true

$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

$statusItem = New-Object System.Windows.Forms.ToolStripMenuItem
$statusItem.Text = 'OpenClaw Node - Starting...'
$statusItem.Enabled = $false

$restartItem = New-Object System.Windows.Forms.ToolStripMenuItem
$restartItem.Text = 'Restart'
$restartItem.add_Click({
    Stop-AllProcesses
    Stop-PortListeners
    Start-Sleep 2
    $global:SshRetried = $false
    $global:NodeRetried = $false
    Start-SshTunnel
    Start-Sleep 2
    Start-OpenClawNode
    $global:Status = 'starting'
    $notifyIcon.ShowBalloonTip(2000, 'OpenClaw', 'Restarted.', 1)
})

$exitItem = New-Object System.Windows.Forms.ToolStripMenuItem
$exitItem.Text = 'Exit'
$exitItem.add_Click({
    Stop-AllProcesses
    $notifyIcon.Visible = $false
    $notifyIcon.Dispose()
    $timer.Stop()
    $timer.Dispose()
    $mutex.ReleaseMutex()
    [System.Windows.Forms.Application]::Exit()
})

[void]$contextMenu.Items.Add($statusItem)
[void]$contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$contextMenu.Items.Add($restartItem)
[void]$contextMenu.Items.Add($exitItem)
$notifyIcon.ContextMenuStrip = $contextMenu

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $CheckIntervalSeconds * 1000
$timer.add_Tick({ Update-TrayStatus })
$timer.Start()

$init = New-Object System.Windows.Forms.Timer
$init.Interval = 5000
$init.add_Tick({ Update-TrayStatus; $init.Stop(); $init.Dispose() })
$init.Start()

$notifyIcon.ShowBalloonTip(3000, 'OpenClaw', 'Starting...', 1)
[System.Windows.Forms.Application]::Run()
