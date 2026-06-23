# 一键打包分享脚本：生成只含运行所需文件的 zip，不含个人数据
# 用法：双击运行，或在 PowerShell 中执行 .\打包发布.ps1

$AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Stamp = Get-Date -Format 'yyyyMMdd'
$PackageName = "工位背单词悬浮窗"
$ZipName = "$PackageName`_$Stamp.zip"
$ZipPath = Join-Path $AppDir $ZipName

# 需要打包的核心文件（运行所需 + 说明）
$IncludeFiles = @(
    'stealth_vocab_wpf.ps1',
    '启动背单词悬浮窗.bat',
    '红宝书词汇.json',
    '使用说明.md',
    '分享说明.txt',
    '打包发布.ps1'
)

# 个人数据 / 旧版残留，绝不打包
$ExcludeFiles = @(
    'stealth_vocab_wpf_settings.json',
    '熟悉词库.json',
    '生词库.json',
    '未分类词库.json',
    'stealth_vocab.py',
    'stealth_vocab_settings.json'
)

Write-Host '正在打包分享包...' -ForegroundColor Cyan
Write-Host "输出: $ZipName"
Write-Host ''

# 校验核心文件齐全
$missing = @()
foreach ($f in $IncludeFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $AppDir $f))) {
        $missing += $f
    }
}
if ($missing.Count -gt 0) {
    Write-Host '[错误] 缺少以下核心文件，无法打包：' -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  - $_" }
    Read-Host '按回车退出'
    exit 1
}

# 删除旧 zip
if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }

# 临时目录组装：zip 内保留一个总文件夹，别人解压后不散文件
$TmpRoot = Join-Path $env:TEMP "vocab_share_$Stamp"
$TmpDir = Join-Path $TmpRoot $PackageName
if (Test-Path -LiteralPath $TmpRoot) { Remove-Item -LiteralPath $TmpRoot -Recurse -Force }
if (Test-Path -LiteralPath $TmpDir) { Remove-Item -LiteralPath $TmpDir -Recurse -Force }
New-Item -ItemType Directory -Path $TmpDir | Out-Null

foreach ($f in $IncludeFiles) {
    Copy-Item -LiteralPath (Join-Path $AppDir $f) -Destination $TmpDir -Force
}

# 打包（要求 PowerShell 5+，Win10 自带 Compress-Archive）
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($TmpRoot, $ZipPath)

# 清理临时目录
Remove-Item -LiteralPath $TmpRoot -Recurse -Force

$size = [math]::Round((Get-Item -LiteralPath $ZipPath).Length / 1KB, 1)
Write-Host ''
Write-Host "打包完成: $ZipName ($size KB)" -ForegroundColor Green
Write-Host "位置: $ZipPath"
Write-Host ''
Write-Host '分享包内容（不含任何个人数据）：'
foreach ($f in $IncludeFiles) { Write-Host "  - $f" }
Write-Host ''
Write-Host '确认未包含：'
foreach ($f in $ExcludeFiles) { Write-Host "  - $f" }
Write-Host ''
Write-Host '收件人解压后双击 启动背单词悬浮窗.bat 即可运行。'
Write-Host '如果 Windows 弹安全提示，选择“仍要运行”即可；程序不需要联网、不需要安装。'
Read-Host '按回车退出'
