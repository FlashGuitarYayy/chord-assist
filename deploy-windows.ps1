<#
和弦助手 Chord Assist —— Windows 安装脚本

在 PowerShell 里：
    .\deploy-windows.ps1                 自动找到 MuseScore 的 Plugins 目录并装进去
    .\deploy-windows.ps1 -List           只列出找到的目录，不动手
    .\deploy-windows.ps1 -Dir "D:\...\Plugins"    指定目录
    .\deploy-windows.ps1 -All            找到几个装几个（默认只装第一个）
    .\deploy-windows.ps1 -Uninstall      卸载

嫌麻烦就双击同目录下的 install.bat。
#>

[CmdletBinding()]
param(
    [string]$Dir,
    [switch]$List,
    [switch]$All,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
# 让中文在控制台里能显示。个别宿主不让改，改不了就算了，不影响安装
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

$Name = 'ChordAssist'
$Src  = Join-Path $PSScriptRoot $Name

function Find-PluginDirs {
    $found = New-Object System.Collections.Generic.List[string]

    function Add-Dir([string]$p) {
        if ([string]::IsNullOrWhiteSpace($p)) { return }
        try { $p = (Resolve-Path -LiteralPath $p -ErrorAction Stop).Path } catch { return }
        if ($found -notcontains $p) { $found.Add($p) }
    }

    # 1) 文档\MuseScore*\Plugins —— 默认位置。用 MyDocuments 取，这样文档被
    #    OneDrive 重定向过也找得到
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if ($docs -and (Test-Path -LiteralPath $docs)) {
        Get-ChildItem -LiteralPath $docs -Directory -Filter 'MuseScore*' -ErrorAction SilentlyContinue |
            ForEach-Object { Add-Dir (Join-Path $_.FullName 'Plugins') }
    }

    # 2) 在 偏好设置 → 文件夹 里改过插件目录的话，MuseScore 会把新路径写进 ini
    foreach ($root in @($env:LOCALAPPDATA, $env:APPDATA)) {
        if (-not $root) { continue }
        $base = Join-Path $root 'MuseScore'
        if (-not (Test-Path -LiteralPath $base)) { continue }
        Get-ChildItem -LiteralPath $base -Filter '*.ini' -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Select-String -LiteralPath $_.FullName -Pattern 'myPlugins\s*=\s*(.+)$' -ErrorAction Stop |
                    ForEach-Object { Add-Dir ($_.Matches[0].Groups[1].Value.Trim().Trim('"')) }
            } catch { }
        }
    }

    return $found
}

function Install-To([string]$base) {
    $dest = Join-Path $base $Name
    if (Test-Path -LiteralPath $dest) {
        Remove-Item -LiteralPath $dest -Recurse -Force
        Write-Host "  覆盖旧版本"
    }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Copy-Item -Path (Join-Path $Src '*') -Destination $dest -Recurse -Force
    Write-Host "  装好了 -> $dest"
}

function Uninstall-From([string]$base) {
    $dest = Join-Path $base $Name
    if (Test-Path -LiteralPath $dest) {
        Remove-Item -LiteralPath $dest -Recurse -Force
        Write-Host "  删掉了 -> $dest"
        return $true
    }
    return $false
}

# ---------------------------------------------------------------------------

# @() 包一层：PowerShell 输出集合时会拆包，一个元素就变成裸字符串，
# 后面的 .Count / foreach 会有惊喜
$dirs = @(if ($Dir) { $Dir } else { Find-PluginDirs })

if ($List) {
    Write-Host "找到这些 MuseScore 插件目录："
    if ($dirs.Count -eq 0) { Write-Host "  （一个都没有）" }
    foreach ($d in $dirs) {
        $mark = if (Test-Path -LiteralPath (Join-Path $d $Name)) { "已装" } else { "    " }
        Write-Host "  [$mark] $d"
    }
    exit 0
}

if ($dirs.Count -eq 0) {
    Write-Host "没找到 MuseScore 的插件目录。" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "常见原因是 MuseScore 装好之后还没启动过 —— 这个目录是第一次运行时才建的。"
    Write-Host "先把 MuseScore 打开一次再跑这个脚本。"
    Write-Host ""
    Write-Host "或者自己指定："
    Write-Host '  .\deploy-windows.ps1 -Dir "$env:USERPROFILE\Documents\MuseScore4\Plugins"'
    exit 1
}

if ($Uninstall) {
    $n = 0
    foreach ($d in $dirs) { if (Uninstall-From $d) { $n++ } }
    if ($n -eq 0) { Write-Host "本来就没装。" } else { Write-Host "`n卸载完了。菜单项如果还在，重启一次 MuseScore 就没了。" }
    exit 0
}

if (-not (Test-Path -LiteralPath $Src)) {
    Write-Host "找不到 $Src" -ForegroundColor Red
    Write-Host "请把 zip 整个解压出来再运行，别只把这个脚本单独拖出来。"
    exit 1
}

if (-not $All -and $dirs.Count -gt 1) {
    Write-Host "找到多个插件目录，默认只装第一个（想全装加 -All）："
    foreach ($d in $dirs) { Write-Host "  $d" }
    Write-Host ""
    $dirs = @($dirs[0])
}

foreach ($d in $dirs) {
    Write-Host "装到 $d"
    Install-To $d
}

Write-Host ""
Write-Host "接下来："
Write-Host "  1. 重启 MuseScore"
Write-Host "  2. 主页 → 插件（Home → Plugins），找到「和弦助手」和「和弦助手 · 环境探针」，两个都打勾启用"
Write-Host "  3. 打开一份吉他谱，在六线谱上点选一个音符"
Write-Host "  4. 菜单 → 插件 → 和弦助手 · 环境探针 → 点「写入测试」→ 把整份报告贴回对话"
Write-Host ""
Write-Host "卸载： .\deploy-windows.ps1 -Uninstall"
