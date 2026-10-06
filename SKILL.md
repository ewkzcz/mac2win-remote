---
name: mac2win-remote
description: 在 Mac 上远程控制一台 Windows 电脑：执行命令、构建测试、运行科学计算与桌面软件（如 MATLAB）、运行后台服务、操作桌面 GUI、截图。当工作目录在 wr 配置的同步根目录（WR_LOCAL_ROOT）下，或用户提到 Windows、远程运行、在 Windows 上测试、打开 Windows 上的软件、看 Windows 屏幕时使用。
---

# Mac → Windows 远程控制

你运行在 Mac 上。本地同步根目录 `$WR_LOCAL_ROOT` 和 Windows 上的 `$WR_REMOTE_ROOT` 保持实时双向同步。
**读写文件在 Mac 上做（Read / Edit / Write），执行命令在 Windows 上做（`wr`）。**

## 了解环境

所有环境相关的值都放在 `~/.config/wr/env` 里，不要自己假设。查看时去掉密钥：

```bash
grep -v '^ST_KEY=' ~/.config/wr/env
```

| 变量 | 含义 |
|---|---|
| `WR_HOST` | SSH 别名（具体主机和用户在 `~/.ssh/config` 里） |
| `WIN_IP` | Windows 的地址，从 Mac 访问 Windows 上的服务时使用 |
| `WR_LOCAL_ROOT` / `WR_REMOTE_ROOT` | Mac / Windows 两边的同步根目录 |
| `WR_TOOLS` | Windows 上的工具目录；`wr` / `wsh` 会自动把它加进 PATH |
| `ST_URL` | 同步服务（Syncthing）的管理地址 |

Windows 的硬件和软件都要现场查询。命令行工具一般在 PATH 里；桌面软件（MATLAB、IDE 等）通常不在，需要通过快捷方式找到可执行文件的完整路径，再用 `& "完整路径" 参数` 调用：

```bash
wsh '$c=Get-CimInstance Win32_ComputerSystem; "{0} 线程 / {1:N0} GB" -f $c.NumberOfLogicalProcessors, ($c.TotalPhysicalMemory/1GB)'
wsh 'Get-Volume | ? DriveLetter | Select DriveLetter,@{n="FreeGB";e={[int]($_.SizeRemaining/1GB)}}'
wsh 'Get-Command git,node,npm,python,pip,dotnet,java,go,cargo -EA SilentlyContinue | Select Name,Source'
wsh 'Get-ChildItem "$env:ProgramData\Microsoft\Windows\Start Menu","$env:APPDATA\Microsoft\Windows\Start Menu","$env:PUBLIC\Desktop","$env:USERPROFILE\Desktop" -Recurse -Filter *.lnk -EA SilentlyContinue | ? Name -match "关键词" | % { (New-Object -ComObject WScript.Shell).CreateShortcut($_.FullName).TargetPath } | Select -Unique'
```

## 能力与命令

| 能力 | 命令 |
|---|---|
| 在项目目录执行命令 | `wr '<PowerShell>'`：必须在 `$WR_LOCAL_ROOT` 下执行，会先等同步完成，返回输出和退出码 |
| 系统级命令（不切换目录） | `wsh '<PowerShell>'`；长脚本用 `wsh <<'EOF' … EOF` |
| 运行不在 PATH 中的程序 | `wr '& "<完整路径>" <参数>'`；参数里带引号时，写成项目里的 `.ps1` 再调用 |
| 后台常驻进程 / 打开 GUI 程序 | `wr 'Start-Interactive.ps1 -Name <名> -Cmd "<命令>"'` |
| 查看后台日志 | `wr 'Get-Content .ai-logs\<名>.log -Tail 80'` |
| 停止后台进程 | `wr 'Stop-Interactive.ps1 -Name <名>'` |
| 列出后台进程 | `wr 'Get-ScheduledTask ai-* \| Select TaskName,State'` |
| 在桌面会话里执行脚本（点击、输入、读窗口），等它跑完 | `wr 'Invoke-Interactive.ps1 -Cmd "& .\<脚本>.ps1"'` |
| 截 Windows 屏幕 | `wshot [名]` 会输出 Mac 本地的 PNG 路径，再用 Read 查看 |
| 查看 Windows 上生成的图片、数据 | 把文件写到项目目录里（不要写进不同步的目录），同步回 Mac 后用 Read 查看 |
| 访问 Windows 上的服务 | `. ~/.config/wr/env; curl --noproxy '*' "http://$WIN_IP:<端口>"`（服务要监听 0.0.0.0，端口要在 Windows 防火墙放行） |
| 传输同步目录以外的文件 | 上传 `scp 本地文件 "$WR_HOST:C:/路径/"`，下载 `scp "$WR_HOST:C:/路径/文件" .` |

## 环境差异（必须遵守）

- `wr` / `wsh` 里运行的是 **PowerShell 7**，不是 bash。要用 `Get-ChildItem`、`Select-String`、`Remove-Item -Recurse -Force`、`$env:X='1'` 这类写法。
- `foreach (...) { ... }` 是语句，后面不能直接接管道，会报"不允许空管道元素"。先赋值再处理：`$r = foreach (...) { ... }; $r | Select -First 50`，或改用管道里的 `ForEach-Object`。
- 外层是 bash：整条命令用**单引号**包住，里面需要引号时用双引号。命令里必须出现单引号，或者超过约 2500 字符时，把它写成项目里的 `.ps1` 文件，再执行 `wr './x.ps1'`。PowerShell 不能用 `\"` 转义引号。
- **不要**直接用 `ssh $WR_HOST '命令'`。那样运行的是 cmd.exe，中文会乱码，报错会变成一大段 XML（CLIXML）。
- **输出编码**：`wr` 按 UTF-8 读取输出。原生 Windows 程序按系统 OEM 代码页输出（中文系统是 936，也就是 GBK），直接看中文会乱码。程序能写 UTF-8 日志的，就读日志；不能的，在 `.ps1` 里按 OEM 代码页解码后再输出（写法见"常见任务"）。
- **工作目录**：`wr` 在当前 Mac 目录对应的 Windows 目录执行，所以当前目录必须在 `$WR_LOCAL_ROOT` 下。Bash 工具每次调用后工作目录会被重置，`cd` 与 `wr` 要写在同一条命令里：`cd "$WR_LOCAL_ROOT/<项目>" && wr './sub/x.ps1'`，脚本路径相对这个目录。有些程序启动后会自己改变工作目录（例如 MATLAB 会回到它自己的启动目录）；`.ps1` 里调用子目录中的 Python 脚本时，先 `Set-Location` 到脚本所在目录，或给出脚本绝对路径。
- 没有 stdin，交互式命令会失败。加上 `-y`、`--yes`，或设置 `$env:CI='1'`；有无界面批处理模式的软件，要用它的批处理模式（例如 `matlab -batch`）。
- SSH 运行在 session 0，不是登录的桌面。直接用 `wr` 启动的进程，命令结束时就会被结束；GUI 窗口也看不到。需要常驻或要显示界面时，用 `Start-Interactive.ps1` 或 `Invoke-Interactive.ps1`。画图类程序用无界面方式直接把图存成文件。
- 不同步的目录以 `$WR_LOCAL_ROOT/.stignore` 为准（一般包括依赖目录、构建产物、`.ai-logs`、`.git`），它们只存在于一边。需要查看 Windows 上的这些目录时用 `wr`。
- Windows 上生成的文件同步回 Mac 需要约 2–3 秒。
- 编译、安装依赖、启动大型软件这类耗时长的操作：调大 Bash 工具的 timeout，或者用 `Start-Interactive.ps1` 放到后台跑，再看日志。
- 远程命令不加载 PowerShell 的个人配置文件，conda 之类的环境不会自动激活。Windows 上常有多个 Python（系统 Python、conda 环境、各项目的 venv），PATH 里的 `python` 未必带所需的包或 GPU 版框架（例如 torch 是 CPU 版）。先逐个检查候选解释器，选定后在脚本里一律用它的绝对路径启动，不要混用。
- 在整块磁盘上递归搜索文件（如对某个盘符根目录 `Get-ChildItem <盘符>:\ -Recurse`）很容易超过 Bash 工具的超时：限定搜索根目录、加 `-Depth`，或放到后台运行再看结果。
- 命令以管理员身份运行：删除文件、改系统设置、关闭用户的程序之前，先问用户。**不要修改 DNS 或代理配置。**
- 结束自己启动的进程时，按 PID 或命令行精确匹配，不要用 `Get-Process python | Stop-Process` 这类按进程名全杀的写法：用户可能同时开着其他 Python 程序（服务、桌面工具等）。按命令行筛选：`Get-CimInstance Win32_Process | ? { $_.Name -eq 'python.exe' -and $_.CommandLine -match '<入口脚本名>' }`（写进 `.ps1` 执行，避免 `-Filter` 里的嵌套引号被外层 bash 吃掉）。结束后再查一次，确认没有残留。

## 常见任务

```bash
cd "$WR_LOCAL_ROOT/<项目>"
wr 'npm install --no-audit --no-fund; npm test'
wr 'python -m pytest -q'
wr 'Start-Interactive.ps1 -Name web -Cmd "npm run dev -- --host 0.0.0.0"'
wr 'Get-Content .ai-logs\web.log -Tail 20'
```

**运行长时间的计算任务（实验、训练，几十分钟以上）**：用 `Start-Interactive.ps1` 放到后台，不要靠一个挂着的 `wr` 会话撑着（SSH 一断进程就会被结束）。启动脚本固定解释器、工作目录和日志位置；进度写进同步目录里的文件，从 Mac 本地读取。

```powershell
# run-exp.ps1    用法: wr 'Start-Interactive.ps1 -Name exp -Cmd "& .\run-exp.ps1 main"'
param([Parameter(Mandatory)][string]$Config)
Set-Location $PSScriptRoot                                  # 显式切到脚本所在目录
$py = '<选定的解释器绝对路径>'
& $py -u run.py $Config 2>&1 | Tee-Object -FilePath "logs\$Config.log"
```

**脚本要支持续跑**：Windows 可能被更新或断电重启，后台进程会被杀。实验脚本按增量落盘（每完成一个单元就写结果文件），启动时先读已有结果、跳过已完成部分（断点续跑）；不要依赖未落盘的内存状态。重启后重新执行同一条启动命令即可接着跑。

查看：`wr 'Get-Content .ai-logs\exp.log -Tail 20'`，或直接在 Mac 上读同步回来的进度文件；停止：`wr 'Stop-Interactive.ps1 -Name exp'`，再按命令行确认没有残留的子进程。

**运行 MATLAB 这类桌面软件的批处理**：在项目里写一个启动脚本，统一处理完整路径、工作目录和输出编码，然后执行 `wr './run-matlab.ps1 <脚本名>'`。脚本里用 `figure('Visible','off')` 和 `exportgraphics` 把图存到项目目录。

```powershell
# run-matlab.ps1
param([Parameter(Mandatory)][string]$Script)
$matlab = '<通过快捷方式查到的 matlab.exe 完整路径>'
$log = Join-Path $env:TEMP "matlab-$PID.log"
& $matlab -batch "cd('$($PWD.Path)'); $Script" -logfile $log *> $null   # 显式 cd；控制台输出是 OEM 代码页，改从 UTF-8 日志读取
$code = $LASTEXITCODE
if (Test-Path $log) { Get-Content $log -Encoding utf8; Remove-Item $log }
exit $code
```

**解码原生程序的输出**（程序没有 UTF-8 日志可读时）：

```powershell
# oem.ps1    用法: wr './oem.ps1 <程序> -ArgList "参数1","参数2"'
param([Parameter(Mandatory)][string]$Exe, [string[]]$ArgList)
[Console]::OutputEncoding = [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage)
$out = & $Exe @ArgList 2>&1 | Out-String
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$out
```

## GUI 操作流程

1. 执行 `wshot s1`，用 Read 查看截图，找到目标位置的坐标。如果 Read 提示了缩放比例，要把坐标乘回原始像素。
2. 在项目里写一个脚本，例如 `.ai-gui/step.ps1`：

```powershell
. Gui.ps1
Get-Windows                    # 列出所有窗口（进程名、标题）
Focus-Window <进程名>          # 激活并最大化
Click <x> <y>                  # 原始像素坐标；-Double 双击，-Right 右键
Send-Text '要输入的文字'        # 通过剪贴板粘贴，支持中文，完成后还原用户的剪贴板
Send-Key Enter                 # 组合键：Send-Key Ctrl,A / Send-Key Win,D
```

3. 执行 `wr 'Invoke-Interactive.ps1 -Cmd "& .\.ai-gui\step.ps1"'`。
4. 再执行 `wshot s2`，检查操作结果。

截图保存在项目的 `.ai-shots/` 里，不要提交到 git。Windows 锁屏或没有登录时，GUI 操作和截图都会失败。

## 出问题时

| 现象 | 处理 |
|---|---|
| 提示缺少配置 `~/.config/wr/env` | 环境还没搭好，请用户按搭建教程完成 |
| 输出里的中文乱码 | 原生程序编码问题，见"环境差异 · 输出编码" |
| 程序报找不到项目里的脚本或文件 | 程序自己改变了工作目录，改用显式路径 |
| 程序退出时打印了报错，但退出码是 0、结果也正常 | 通常来自软件自身的退出脚本或插件，不影响结果；先确认结果，不要擅自修改软件配置 |
| `wr` 卡住约 30 秒才执行 | 同步异常，查看 `$ST_URL` |
| SSH 卡住或断开 | 执行 `ssh -O exit "$WR_HOST"` 后重试；用 `tailscale status` 确认 Windows 在线 |
| GUI 操作或截图失败 | Windows 锁屏或没有登录，请用户处理 |
| `wr` 报找不到 `./x.ps1`，或 Python 报 `can't find '__main__' module` | 当前目录不在 `$WR_LOCAL_ROOT` 下（Bash 工具重置了目录），或脚本没有切到自己所在目录；`cd` 与 `wr` 写在同一条命令里，`.ps1` 里加 `Set-Location $PSScriptRoot` |
| PowerShell 报"不允许空管道元素" | `foreach` 语句后面直接接了管道，见"环境差异" |
| `Get-CimInstance -Filter` 报"无效查询" | 过滤条件里的引号被外层 bash 改掉了；写进 `.ps1`，或改用 `Where-Object` 筛选 |
| 装了 GPU 却只能用 CPU，或报缺包 | 用的不是对的解释器；逐个检查候选解释器，改用绝对路径 |
| 重启后 SSH 连不上，或 `Get-Service sshd` 报找不到（sshd 服务注册丢失） | 先请用户在 Windows 管理员 PowerShell 执行 `& 'C:\tools\Repair-Sshd.ps1'`（或手工 `sc.exe create sshd binPath= "\"C:\Program Files\OpenSSH\sshd.exe\"" start= auto; Start-Service sshd`）；能连上后执行 `wsh 'Repair-Sshd.ps1 -Register'`，注册 SYSTEM 计划任务（开机 + 每 5 分钟检查，缺失就重建）。日志 `C:\ProgramData\wr\repair-sshd.log` |
| 长任务被重启杀掉（`ai-*` 任务进程消失、`Get-CimInstance Win32_OperatingSystem` 的 `LastBootUpTime` 变新） | 查原因：`Get-WinEvent -FilterHashtable @{LogName='System';Id=41,1074,6005,6006,6008,1001}`，1074 的进程是 `MoUsoCoreWorker.exe` 即自动更新重启，41/6008 是断电或蓝屏。更新重启的防范：`wsh 'Harden-Windows.ps1'`（登录用户在线时不自动重启、固定活动时间、交流电不睡眠；原值存 `C:\ProgramData\wr\harden-backup.json`，`-Revert` 可恢复）。已被杀的任务按"脚本要支持续跑"重新启动 |
| 后台计算进程无声退出 | 查 Windows 应用日志：`Get-WinEvent -FilterHashtable @{LogName='Application'; StartTime=(Get-Date).AddHours(-1)} \| ? Message -match 'python'`，看崩溃模块与异常码（`0xc0000005` 多半是内存不足或驱动问题），再看同一时间的系统日志 |
| Mac 上 `sed -i` 报 `invalid command code` | macOS 的 sed 是 BSD 版，原地修改要写 `sed -i ''`；或直接用文件编辑工具修改 |

## 源码

| 文件 | 安装位置 | 作用 |
|---|---|---|
| `install.sh` | 仓库根目录，执行一次 | 把本技能链接到 `~/.claude/skills/mac2win-remote`（安装或覆盖更新，支持 `--dry-run`） |
| `scripts/mac/wr` | Mac 的 PATH 中（如 `~/.local/bin/`） | 在当前目录对应的 Windows 目录执行 PowerShell |
| `scripts/mac/wr-flush` | 同上 | 让 Syncthing 立即扫描，并等 Windows 同步完成 |
| `scripts/mac/wsh` | 同上 | 在 Windows 上执行 PowerShell（不切换目录） |
| `scripts/mac/wshot` | 同上 | 截 Windows 屏幕，并等图片同步回 Mac |
| `scripts/windows/Start-Interactive.ps1` | Windows 的 `$WR_TOOLS` | 在桌面会话里后台运行命令，输出写日志 |
| `scripts/windows/Stop-Interactive.ps1` | 同上 | 结束后台命令及它启动的子进程 |
| `scripts/windows/Invoke-Interactive.ps1` | 同上 | 在桌面会话里执行脚本，等它跑完并返回输出 |
| `scripts/windows/Screenshot.ps1` | 同上 | 在桌面会话里截全屏 |
| `scripts/windows/Gui.ps1` | 同上 | 窗口、点击、键盘、文本输入函数 |
| `scripts/windows/Harden-Windows.ps1` | 同上 | 防自动更新重启与睡眠打断长任务，幂等，保存原值，`-Revert` 恢复 |
| `scripts/windows/Repair-Sshd.ps1` | 同上 | sshd 服务丢失时自动重建并启动，补防火墙规则，顺带报告 Syncthing 状态；`-Register` 注册为开机 + 每 5 分钟的计划任务 |

安装或更新（在技能目录下执行；技能说明本身用 `./install.sh`）：

```bash
. ~/.config/wr/env
install -m 755 scripts/mac/* ~/.local/bin/
scp -q scripts/windows/*.ps1 "$WR_HOST:$(printf '%s' "$WR_TOOLS" | tr '\\' '/')/"
```

`scripts/windows/` 有改动或首次安装后，在 Windows 上执行一次（可重复执行）：

```bash
wsh 'Harden-Windows.ps1; Repair-Sshd.ps1 -Register'
```
