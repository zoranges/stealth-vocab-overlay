Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$WordsFile = Join-Path $AppDir '红宝书词汇.json'
$SettingsFile = Join-Path $AppDir 'stealth_vocab_wpf_settings.json'
$FamiliarFile = Join-Path $AppDir '熟悉词库.json'
$UnknownFile = Join-Path $AppDir '生词库.json'
$UnclassifiedFile = Join-Path $AppDir '未分类词库.json'

$Hotkeys = [ordered]@{
    F6 = 0x75; F7 = 0x76; F8 = 0x77; F9 = 0x78; F10 = 0x79; F11 = 0x7A; F12 = 0x7B
    PageDown = 0x22; Insert = 0x2D
}
$FocusKeys = @('A','D','F','J','K','Q','W','E','Z','X','C','Space','Left','Right','Up','Down')

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class HotKeyNative {
  [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
  [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
"@

$DefaultSettings = [ordered]@{
    x = 80; y = 80; width = 390; height = 116
    opacity = 1.0
    wordSize = 28; meaningSize = 15; infoSize = 10
    wordColor = '#f8fafc'; meaningColor = '#e5e7eb'; infoColor = '#cbd5e1'
    backdrop = $false; backdropOpacity = 0.14
    textShadow = $true; shadowBlur = 7; shadowOpacity = 0.85
    visibilityFixV3 = $true
    autoMode = $true; intervalMs = 5000; hotkey = 'F8'
    focusFamiliarKey = 'A'; focusUnknownKey = 'D'
    showMeaning = $true; showPos = $true; showPage = $true; showIndex = $true; showMode = $true
    topmost = $true; randomOrder = $false; locked = $false
    focusMode = $false; studyDeck = '全部'
    lastPositionByDeck = @{}
}

function Copy-Settings($source) {
    $settings = [ordered]@{}
    foreach ($key in $DefaultSettings.Keys) { $settings[$key] = $DefaultSettings[$key] }
    if ($source) {
        foreach ($p in $source.PSObject.Properties) {
            if ($settings.Contains($p.Name)) { $settings[$p.Name] = $p.Value }
        }
    }
    return $settings
}

function Load-Settings {
    $settings = $null
    if (Test-Path -LiteralPath $SettingsFile) {
        try { $settings = Copy-Settings ((Get-Content -LiteralPath $SettingsFile -Raw -Encoding UTF8) | ConvertFrom-Json) } catch {}
    }
    if (-not $settings) { $settings = Copy-Settings $null }
    if (-not $settings.visibilityFixV3) {
        if ($settings.wordColor -eq '#111111' -and $settings.meaningColor -eq '#222222') {
            $settings.wordColor = '#f8fafc'
            $settings.meaningColor = '#e5e7eb'
            $settings.infoColor = '#cbd5e1'
            $settings.opacity = 1.0
        }
        $settings.visibilityFixV3 = $true
    }
    return $settings
}

function Save-Settings {
    $Settings | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $SettingsFile -Encoding UTF8
}

function Load-WordSet($path) {
    $set = @{}
    if (Test-Path -LiteralPath $path) {
        try {
            $items = (Get-Content -LiteralPath $path -Raw -Encoding UTF8) | ConvertFrom-Json
            foreach ($item in $items) {
                $word = [string]$item
                if ($word) { $set[$word.ToLower()] = $true }
            }
        } catch {}
    }
    return $set
}

function Save-WordSet($path, $set) {
    $arr = @($set.Keys | Sort-Object)
    if ($arr.Count -eq 0) {
        '[]' | Set-Content -LiteralPath $path -Encoding UTF8
    } else {
        $arr | ConvertTo-Json -Depth 2 | Set-Content -LiteralPath $path -Encoding UTF8
    }
}

function Sync-UnclassifiedWordSet {
    if (-not $Words) { return }
    $set = @{}
    foreach ($w in $Words) {
        $key = Word-Key $w
        if (-not $FamiliarWords.ContainsKey($key) -and -not $UnknownWords.ContainsKey($key)) {
            $set[$key] = $true
        }
    }
    Save-WordSet $UnclassifiedFile $set
}

function Reload-ExternalWordSets {
    $script:FamiliarWords = Load-WordSet $FamiliarFile
    $script:UnknownWords = Load-WordSet $UnknownFile
    Sync-UnclassifiedWordSet
}

function Meaning-Text($entry) {
    if (-not $entry.meanings -or $entry.meanings.Count -eq 0) { return '释义待补充' }
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($group in $entry.meanings) {
        if (-not $group.meanings -or $group.meanings.Count -eq 0) { continue }
        $text = ($group.meanings | ForEach-Object { [string]$_ }) -join '；'
        if ($Settings.showPos -and $group.pos) { $parts.Add("$($group.pos) $text") } else { $parts.Add($text) }
    }
    if ($parts.Count -eq 0) { return '释义待补充' }
    return ($parts -join '  |  ')
}

# 根据文字颜色亮度自动选择反色阴影，保证任意背景下都清晰
function Shadow-Color($hex) {
    $h = [string]$hex -replace '#',''
    if ($h.Length -lt 6) { return '#000000' }
    $r = [Convert]::ToInt32($h.Substring(0,2),16)
    $g = [Convert]::ToInt32($h.Substring(2,2),16)
    $b = [Convert]::ToInt32($h.Substring(4,2),16)
    $lum = 0.299*$r + 0.587*$g + 0.114*$b
    if ($lum -ge 128) { return '#000000' } else { return '#FFFFFF' }
}

function Apply-TextShadow($element, $colorHex) {
    if ([bool]$Settings.textShadow) {
        $sc = Shadow-Color $colorHex
        $eff = New-Object System.Windows.Media.Effects.DropShadowEffect
        $eff.Color = [System.Windows.Media.ColorConverter]::ConvertFromString($sc)
        $eff.BlurRadius = [double]$Settings.shadowBlur
        $eff.ShadowDepth = 0
        $eff.Opacity = [double]$Settings.shadowOpacity
        $element.Effect = $eff
    } else {
        $element.Effect = $null
    }
}

if (-not (Test-Path -LiteralPath $WordsFile)) {
    [System.Windows.MessageBox]::Show("没有找到词库文件：`n$WordsFile`n`n请确认整个文件夹完整复制，不要只复制单个文件。", '缺少词库') | Out-Null
    exit 1
}

$Settings = Load-Settings
try {
    $Words = (Get-Content -LiteralPath $WordsFile -Raw -Encoding UTF8) | ConvertFrom-Json
} catch {
    [System.Windows.MessageBox]::Show("词库文件解析失败：`n$($_.Exception.Message)", '词库错误') | Out-Null
    exit 1
}
$FamiliarWords = Load-WordSet $FamiliarFile
$UnknownWords = Load-WordSet $UnknownFile
$ActiveIndices = New-Object System.Collections.Generic.List[int]
$Index = 0
$Timer = New-Object System.Windows.Threading.DispatcherTimer
$WheelTimer = New-Object System.Windows.Threading.DispatcherTimer
$SaveTimer = New-Object System.Windows.Threading.DispatcherTimer
$SaveTimer.Interval = [TimeSpan]::FromMilliseconds(400)
$SaveTimer.Add_Tick({ $SaveTimer.Stop(); Save-Settings })
$WheelDelta = 0
$IsPointerDown = $false
$IsDragging = $false
$DragStartPoint = $null
$DragWindowLeft = 0
$DragWindowTop = 0
$DragStartSource = $null
$HotKeyId = 2208
$Source = $null
$script:SettingsWindow = $null
$script:ListWindow = $null
$script:StartBoxControl = $null
$script:StartHintControl = $null

$Window = New-Object System.Windows.Window
$Window.Title = '工位背单词悬浮窗'
$Window.WindowStyle = 'None'
$Window.AllowsTransparency = $true
$Window.Background = [System.Windows.Media.Brushes]::Transparent
$Window.ShowInTaskbar = $true
$Window.Topmost = [bool]$Settings.topmost
$Window.ResizeMode = 'NoResize'
$Window.WindowStartupLocation = 'Manual'
$Window.Focusable = $true
$Window.UseLayoutRounding = $true
$Window.SnapsToDevicePixels = $true
$Window.Left = [double]$Settings.x
$Window.Top = [double]$Settings.y
$Window.Width = [double]$Settings.width
$Window.Height = [double]$Settings.height
$Window.Opacity = [double]$Settings.opacity

$Root = New-Object System.Windows.Controls.Grid
$Root.Background = [System.Windows.Media.Brushes]::Transparent
$Root.Margin = '0'
$Window.Content = $Root

$Backdrop = New-Object System.Windows.Controls.Border
$Backdrop.CornerRadius = '6'
$Backdrop.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#111827')
$Backdrop.Opacity = [double]$Settings.backdropOpacity
$Backdrop.Visibility = if ($Settings.backdrop) { 'Visible' } else { 'Collapsed' }
$Root.Children.Add($Backdrop) | Out-Null

$Panel = New-Object System.Windows.Controls.StackPanel
$Panel.Background = [System.Windows.Media.Brushes]::Transparent
$Panel.Orientation = 'Vertical'
$Panel.Margin = '8,4,8,4'
$Root.Children.Add($Panel) | Out-Null

$WordText = New-Object System.Windows.Controls.TextBlock
$WordText.FontFamily = 'Segoe UI Semibold'
$WordText.FontSize = [double]$Settings.wordSize
$WordText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Settings.wordColor)
$WordText.TextWrapping = 'NoWrap'
$WordText.TextTrimming = 'CharacterEllipsis'
$WordText.SnapsToDevicePixels = $true
[System.Windows.Media.TextOptions]::SetTextFormattingMode($WordText, [System.Windows.Media.TextFormattingMode]::Display)
[System.Windows.Media.TextOptions]::SetTextRenderingMode($WordText, [System.Windows.Media.TextRenderingMode]::Grayscale)
[System.Windows.Media.TextOptions]::SetTextHintingMode($WordText, [System.Windows.Media.TextHintingMode]::Fixed)
Apply-TextShadow $WordText $Settings.wordColor
$Panel.Children.Add($WordText) | Out-Null

$MeaningText = New-Object System.Windows.Controls.TextBlock
$MeaningText.FontFamily = 'Microsoft YaHei UI'
$MeaningText.FontSize = [double]$Settings.meaningSize
$MeaningText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Settings.meaningColor)
$MeaningText.TextWrapping = 'Wrap'
$MeaningText.TextTrimming = 'CharacterEllipsis'
$MeaningText.Margin = '0,2,0,0'
$MeaningText.SnapsToDevicePixels = $true
[System.Windows.Media.TextOptions]::SetTextFormattingMode($MeaningText, [System.Windows.Media.TextFormattingMode]::Display)
[System.Windows.Media.TextOptions]::SetTextRenderingMode($MeaningText, [System.Windows.Media.TextRenderingMode]::Grayscale)
[System.Windows.Media.TextOptions]::SetTextHintingMode($MeaningText, [System.Windows.Media.TextHintingMode]::Fixed)
Apply-TextShadow $MeaningText $Settings.meaningColor
$Panel.Children.Add($MeaningText) | Out-Null

$InfoText = New-Object System.Windows.Controls.TextBlock
$InfoText.FontFamily = 'Segoe UI'
$InfoText.FontSize = [double]$Settings.infoSize
$InfoText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Settings.infoColor)
$InfoText.Margin = '0,4,0,0'
$InfoText.SnapsToDevicePixels = $true
[System.Windows.Media.TextOptions]::SetTextFormattingMode($InfoText, [System.Windows.Media.TextFormattingMode]::Display)
[System.Windows.Media.TextOptions]::SetTextRenderingMode($InfoText, [System.Windows.Media.TextRenderingMode]::Grayscale)
[System.Windows.Media.TextOptions]::SetTextHintingMode($InfoText, [System.Windows.Media.TextHintingMode]::Fixed)
Apply-TextShadow $InfoText $Settings.infoColor
$Panel.Children.Add($InfoText) | Out-Null

function Word-Key($entry) {
    return ([string]$entry.english).ToLower()
}

function Rebuild-StudyDeck {
    Reload-ExternalWordSets
    $ActiveIndices.Clear()
    for ($i = 0; $i -lt $Words.Count; $i++) {
        $key = Word-Key $Words[$i]
        $include = $true
        switch ([string]$Settings.studyDeck) {
            '未分类' { $include = (-not $FamiliarWords.ContainsKey($key)) -and (-not $UnknownWords.ContainsKey($key)) }
            '熟悉' { $include = $FamiliarWords.ContainsKey($key) }
            '生词' { $include = $UnknownWords.ContainsKey($key) }
            default { $include = $true }
        }
        if ($include) { $ActiveIndices.Add($i) | Out-Null }
    }
    if ($ActiveIndices.Count -eq 0 -or $script:Index -ge $ActiveIndices.Count) { $script:Index = 0 }
}

function Current-Word {
    if ($ActiveIndices.Count -eq 0) { return $null }
    return $Words[$ActiveIndices[$Index]]
}

function Ensure-PositionMap {
    $map = $Settings['lastPositionByDeck']
    if ($map -is [System.Collections.IDictionary]) { return $map }
    $newMap = @{}
    if ($map) {
        foreach ($p in $map.PSObject.Properties) {
            $newMap[$p.Name] = [int]$p.Value
        }
    }
    $Settings['lastPositionByDeck'] = $newMap
    return $newMap
}

function Save-CurrentStudyPosition {
    if ($ActiveIndices.Count -le 0) { return }
    $map = Ensure-PositionMap
    $map[[string]$Settings.studyDeck] = [int]$script:Index
}

function Restore-StudyPosition {
    $map = Ensure-PositionMap
    $deck = [string]$Settings.studyDeck
    $saved = 0
    if ($map.Contains($deck)) { $saved = [int]$map[$deck] }
    if ($ActiveIndices.Count -le 0) {
        $script:Index = 0
    } else {
        $script:Index = [Math]::Max(0, [Math]::Min($saved, $ActiveIndices.Count - 1))
    }
}

function Jump-ToStudyNumber($number) {
    Rebuild-StudyDeck
    if ($ActiveIndices.Count -eq 0) {
        Refresh-Word
        return
    }
    $target = [int]$number - 1
    if ($target -lt 0) { $target = 0 }
    if ($target -ge $ActiveIndices.Count) { $target = $ActiveIndices.Count - 1 }
    $script:Index = $target
    Refresh-Word
    $Window.UpdateLayout()
    $Window.Activate() | Out-Null
    $Window.Focus() | Out-Null
    Schedule-Timer
    Save-Settings
}

function Import-WordSetFromDialog($kind) {
    $dialog = New-Object Microsoft.Win32.OpenFileDialog
    $dialog.Title = if ($kind -eq 'familiar') { '选择熟悉词库 JSON' } else { '选择生词库 JSON' }
    $dialog.Filter = 'JSON files (*.json)|*.json|All files (*.*)|*.*'
    $dialog.Multiselect = $false
    if ($dialog.ShowDialog() -ne $true) { return }

    $set = Load-WordSet $dialog.FileName
    if ($kind -eq 'familiar') {
        $script:FamiliarWords = $set
        foreach ($key in @($script:FamiliarWords.Keys)) {
            if ($script:UnknownWords.ContainsKey($key)) { $script:UnknownWords.Remove($key) }
        }
    } else {
        $script:UnknownWords = $set
        foreach ($key in @($script:UnknownWords.Keys)) {
            if ($script:FamiliarWords.ContainsKey($key)) { $script:FamiliarWords.Remove($key) }
        }
    }
    Save-WordSet $FamiliarFile $script:FamiliarWords
    Save-WordSet $UnknownFile $script:UnknownWords
    Rebuild-StudyDeck
    Restore-StudyPosition
    Refresh-Word
    Schedule-Timer
    [System.Windows.MessageBox]::Show("导入完成。`n熟悉词：$($script:FamiliarWords.Count)`n生词：$($script:UnknownWords.Count)`n未分类词库已自动更新。", '导入完成') | Out-Null
}

function Mark-CurrentWord($kind) {
    if ($ActiveIndices.Count -eq 0) { return }
    $oldAbsIndex = $ActiveIndices[$Index]
    $entry = Current-Word
    $key = Word-Key $entry
    if ($kind -eq 'familiar') {
        $FamiliarWords[$key] = $true
        if ($UnknownWords.ContainsKey($key)) { $UnknownWords.Remove($key) }
    } else {
        $UnknownWords[$key] = $true
        if ($FamiliarWords.ContainsKey($key)) { $FamiliarWords.Remove($key) }
    }
    Save-WordSet $FamiliarFile $FamiliarWords
    Save-WordSet $UnknownFile $UnknownWords
    if ($Settings.studyDeck -ne '全部') {
        Rebuild-StudyDeck
        if ($ActiveIndices.Count -eq 0) {
            $script:Index = 0
        } else {
            $nextPos = -1
            for ($i = 0; $i -lt $ActiveIndices.Count; $i++) {
                if ($ActiveIndices[$i] -gt $oldAbsIndex) {
                    $nextPos = $i
                    break
                }
            }
            if ($nextPos -lt 0) { $nextPos = 0 }
            $script:Index = $nextPos
        }
        Refresh-Word
        Schedule-Timer
    } else {
        Next-Word
    }
}

function Refresh-Word {
    $entry = Current-Word
    if (-not $entry) {
        $WordText.Text = 'No words in this deck'
        $MeaningText.Text = ''
        $InfoText.Text = "$($Settings.studyDeck) 0/0"
        Save-CurrentStudyPosition
        return
    }
    $WordText.Text = [string]$entry.english
    if ($Settings.showMeaning) {
        $MeaningText.Visibility = 'Visible'
        $MeaningText.Text = Meaning-Text $entry
    } else {
        $MeaningText.Visibility = 'Collapsed'
    }
    $info = New-Object System.Collections.Generic.List[string]
    if ($Settings.showPage) { $info.Add("p.$($entry.page)") }
    if ($Settings.showIndex) { $info.Add("$($Index + 1)/$($ActiveIndices.Count)") }
    if ($Settings.showMode) {
        $deckLabel = [string]$Settings.studyDeck
        if ($Settings.focusMode) { $info.Add("专注 · $deckLabel · $($Settings.focusFamiliarKey)熟/$($Settings.focusUnknownKey)生") }
        elseif ($Settings.autoMode) { $info.Add("自动 · $deckLabel") }
        else { $info.Add("手动 $($Settings.hotkey) · $deckLabel") }
    }
    $InfoText.Text = ($info -join '  ·  ')
    Save-CurrentStudyPosition
    $SaveTimer.Stop()
    $SaveTimer.Start()
}

function Apply-Visuals {
    $Window.Width = [double]$Settings.width
    $Window.Height = [double]$Settings.height
    $Window.MinWidth = [double]$Settings.width
    $Window.MinHeight = [double]$Settings.height
    $Window.MaxWidth = [double]$Settings.width
    $Window.MaxHeight = [double]$Settings.height
    $Window.Opacity = [double]$Settings.opacity
    $Window.Topmost = [bool]$Settings.topmost
    $Backdrop.Visibility = if ($Settings.backdrop) { 'Visible' } else { 'Collapsed' }
    $Backdrop.Opacity = [double]$Settings.backdropOpacity
    $WordText.FontSize = [double]$Settings.wordSize
    $MeaningText.FontSize = [double]$Settings.meaningSize
    $InfoText.FontSize = [double]$Settings.infoSize
    $WordText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Settings.wordColor)
    $MeaningText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Settings.meaningColor)
    $InfoText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Settings.infoColor)
    Apply-TextShadow $WordText $Settings.wordColor
    Apply-TextShadow $MeaningText $Settings.meaningColor
    Apply-TextShadow $InfoText $Settings.infoColor
    Refresh-Word
}

function Schedule-Timer {
    $Timer.Stop()
    if ($Settings.autoMode -and -not $Settings.focusMode) {
        $Timer.Interval = [TimeSpan]::FromMilliseconds([int]$Settings.intervalMs)
        $Timer.Start()
    }
}

function Next-Word {
    if ($ActiveIndices.Count -eq 0) { Rebuild-StudyDeck }
    if ($ActiveIndices.Count -eq 0) { Refresh-Word; return }
    if ($Settings.randomOrder) { $script:Index = Get-Random -Minimum 0 -Maximum $ActiveIndices.Count }
    else { $script:Index = ($script:Index + 1) % $ActiveIndices.Count }
    Refresh-Word
    Schedule-Timer
}

function Prev-Word {
    if ($ActiveIndices.Count -eq 0) { Rebuild-StudyDeck }
    if ($ActiveIndices.Count -eq 0) { Refresh-Word; return }
    $script:Index = ($script:Index - 1 + $ActiveIndices.Count) % $ActiveIndices.Count
    Refresh-Word
    Schedule-Timer
}

function Queue-Wheel($delta) {
    $script:WheelDelta += [int]$delta
    if (-not $WheelTimer.IsEnabled) { $WheelTimer.Start() }
}

function Handle-AppKey($keyName) {
    if ($Settings.focusMode -and $keyName -eq [string]$Settings.focusFamiliarKey) {
        Mark-CurrentWord 'familiar'
        return $true
    }
    if ($Settings.focusMode -and $keyName -eq [string]$Settings.focusUnknownKey) {
        Mark-CurrentWord 'unknown'
        return $true
    }
    if ($keyName -eq 'Right' -or $keyName -eq 'Space') {
        Next-Word
        return $true
    }
    if ($keyName -eq 'Left') {
        Prev-Word
        return $true
    }
    if ($keyName -eq 'Enter') {
        Open-Settings
        return $true
    }
    if ($keyName -eq 'Escape' -and $Settings.focusMode) {
        $Settings.focusMode = $false
        Refresh-Word
        Schedule-Timer
        Save-Settings
        return $true
    }
    return $false
}

function Register-Hotkey {
    if ($Source) {
        [HotKeyNative]::UnregisterHotKey($Source.Handle, $HotKeyId) | Out-Null
        $vk = [uint32]$Hotkeys[$Settings.hotkey]
        [HotKeyNative]::RegisterHotKey($Source.Handle, $HotKeyId, 0, $vk) | Out-Null
    }
}

function Open-List {
    if ($script:ListWindow -and $script:ListWindow.IsLoaded) {
        $script:ListWindow.Activate() | Out-Null
        return
    }
    Rebuild-StudyDeck
    Restore-StudyPosition
    Refresh-Word
    $ListWindow = New-Object System.Windows.Window
    $script:ListWindow = $ListWindow
    $ListWindow.Title = '单词目录'
    $ListWindow.Width = 780
    $ListWindow.Height = 540
    $ListWindow.Topmost = $true
    $ListWindow.Add_Closed({ $script:ListWindow = $null })
    $Dock = New-Object System.Windows.Controls.DockPanel
    $Dock.Margin = '10'
    $ListWindow.Content = $Dock

    # 顶部搜索行
    $FilterRow = New-Object System.Windows.Controls.DockPanel
    $FilterRow.Margin = '0,0,0,8'
    [System.Windows.Controls.DockPanel]::SetDock($FilterRow, 'Top')
    $Dock.Children.Add($FilterRow) | Out-Null

    $Search = New-Object System.Windows.Controls.TextBox
    $Search.ToolTip = '搜索单词、页码或释义'
    $FilterRow.Children.Add($Search) | Out-Null

    $CountText = New-Object System.Windows.Controls.TextBlock
    $CountText.Margin = '0,0,0,8'
    [System.Windows.Controls.DockPanel]::SetDock($CountText, 'Top')
    $Dock.Children.Add($CountText) | Out-Null
    $Tabs = New-Object System.Windows.Controls.TabControl
    $Dock.Children.Add($Tabs) | Out-Null

    function New-WordListView {
        $lv = New-Object System.Windows.Controls.ListView
        $gv = New-Object System.Windows.Controls.GridView
        $lv.View = $gv
        foreach ($col in @(
            @{ Header = '#'; Width = 54; Binding = 'Number' },
            @{ Header = '单词'; Width = 150; Binding = 'Word' },
            @{ Header = '页码'; Width = 58; Binding = 'Page' },
            @{ Header = '词库'; Width = 74; Binding = 'State' },
            @{ Header = '释义'; Width = 410; Binding = 'Meaning' }
        )) {
            $column = New-Object System.Windows.Controls.GridViewColumn
            $column.Header = $col.Header
            $column.Width = $col.Width
            $column.DisplayMemberBinding = New-Object System.Windows.Data.Binding($col.Binding)
            $gv.Columns.Add($column) | Out-Null
        }
        return $lv
    }

    $AllList = New-WordListView
    $UnclassifiedList = New-WordListView
    $FamiliarList = New-WordListView
    $UnknownList = New-WordListView

    foreach ($col in @(
        @{ Header = '全部'; List = $AllList },
        @{ Header = '未分类'; List = $UnclassifiedList },
        @{ Header = '熟悉词库'; List = $FamiliarList },
        @{ Header = '生词库'; List = $UnknownList }
    )) {
        $tab = New-Object System.Windows.Controls.TabItem
        $tab.Header = $col.Header
        $tab.Content = $col.List
        $Tabs.Items.Add($tab) | Out-Null
    }

    # 预构建缓存，避免每次按键都重算释义
    $cache = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $Words.Count; $i++) {
        $w = $Words[$i]
        $key = Word-Key $w
        $state = '未分类'
        if ($FamiliarWords.ContainsKey($key)) { $state = '熟悉' }
        elseif ($UnknownWords.ContainsKey($key)) { $state = '生词' }
        $meaning = Meaning-Text $w
        $line = "$($i + 1) $($w.english) p.$($w.page) $state $meaning"
        $cache.Add([pscustomobject]@{
            Index = $i
            Number = $i + 1
            Word = [string]$w.english
            Page = [string]$w.page
            State = $state
            Meaning = $meaning
            Lower = $line.ToLower()
        })
    }

    $fillList = {
        param($searchBox, $deckBox)
        foreach ($lv in @($AllList, $UnclassifiedList, $FamiliarList, $UnknownList)) { $lv.Items.Clear() }
        $q = $searchBox.Text.ToLower()
        $counts = @{ '全部' = 0; '未分类' = 0; '熟悉' = 0; '生词' = 0 }
        foreach ($c in $cache) {
            if ($q -and -not $c.Lower.Contains($q)) { continue }
            $item = New-Object System.Windows.Controls.ListViewItem
            $item.Content = $c
            $item.Tag = $c.Index
            if ($c.State -eq '熟悉') {
                $item.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#15803d')
            } elseif ($c.State -eq '生词') {
                $item.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#b91c1c')
                $item.FontWeight = [System.Windows.FontWeights]::SemiBold
            }
            $AllList.Items.Add($item) | Out-Null
            $counts['全部']++

            $target = $null
            if ($c.State -eq '未分类') { $target = $UnclassifiedList; $counts['未分类']++ }
            elseif ($c.State -eq '熟悉') { $target = $FamiliarList; $counts['熟悉']++ }
            elseif ($c.State -eq '生词') { $target = $UnknownList; $counts['生词']++ }
            if ($target) {
                $copy = New-Object System.Windows.Controls.ListViewItem
                $copy.Content = $c
                $copy.Tag = $c.Index
                if ($c.State -eq '熟悉') {
                    $copy.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#15803d')
                } elseif ($c.State -eq '生词') {
                    $copy.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#b91c1c')
                    $copy.FontWeight = [System.Windows.FontWeights]::SemiBold
                }
                $target.Items.Add($copy) | Out-Null
            }
        }
        $CountText.Text = "全部 $($counts['全部'])；未分类 $($counts['未分类'])；熟悉词库 $($counts['熟悉'])；生词库 $($counts['生词'])；本次背诵词库 $($Settings.studyDeck)：$($ActiveIndices.Count)"
    }
    $Search.Add_TextChanged({ & $fillList $Search $null })
    $jumpFromList = {
        param($sender, $eventArgs)
        if ($sender.SelectedItem) {
            $absIdx = [int]$sender.SelectedItem.Tag
            # 词表存的是绝对下标，需映射到当前词库的位置
            $pos = $ActiveIndices.IndexOf($absIdx)
            if ($pos -ge 0) {
                $script:Index = $pos
            } else {
                # 该词不在当前词库，切回全部后再定位
                $Settings.studyDeck = '全部'
                Rebuild-StudyDeck
                Save-Settings
                $script:Index = $ActiveIndices.IndexOf($absIdx)
                if ($script:Index -lt 0) { $script:Index = 0 }
            }
            Refresh-Word
            $Window.Activate() | Out-Null
        }
    }
    foreach ($lv in @($AllList, $UnclassifiedList, $FamiliarList, $UnknownList)) {
        $lv.Add_MouseDoubleClick($jumpFromList)
    }
    & $fillList $Search $null
    $ListWindow.Show() | Out-Null
}

function Open-Settings {
    if ($script:SettingsWindow -and $script:SettingsWindow.IsLoaded) {
        $script:SettingsWindow.Activate() | Out-Null
        return
    }
    $SettingsWindow = New-Object System.Windows.Window
    $script:SettingsWindow = $SettingsWindow
    $SettingsWindow.Title = '悬浮窗设置'
    $SettingsWindow.Width = 430
    $SettingsWindow.Height = 620
    $SettingsWindow.Topmost = $true
    $SettingsWindow.ResizeMode = 'NoResize'
    $SettingsWindow.Add_Closed({ $script:SettingsWindow = $null })
    $Scroll = New-Object System.Windows.Controls.ScrollViewer
    $Stack = New-Object System.Windows.Controls.StackPanel
    $Stack.Margin = '14'
    $Scroll.Content = $Stack
    $SettingsWindow.Content = $Scroll

    function Add-Slider($label, $key, $min, $max, $factor) {
        $row = New-Object System.Windows.Controls.StackPanel
        $row.Margin = '0,0,0,8'
        $txt = New-Object System.Windows.Controls.TextBlock
        $txt.Text = $label
        $s = New-Object System.Windows.Controls.Slider
        $s.Minimum = $min; $s.Maximum = $max
        $s.Value = [double]$Settings[$key] / $factor
        $s.Tag = [pscustomobject]@{ Key = $key; Factor = $factor }
        $s.Add_ValueChanged({
            param($sender, $eventArgs)
            if (-not $sender.Tag) { return }
            $sliderKey = [string]$sender.Tag.Key
            $sliderFactor = [double]$sender.Tag.Factor
            if ($sliderKey -eq 'opacity') {
                $Settings[$sliderKey] = [double]$sender.Value
            } else {
                $Settings[$sliderKey] = [int]([double]$sender.Value * $sliderFactor)
            }
            Apply-Visuals; Schedule-Timer; Save-Settings
        })
        $row.Children.Add($txt) | Out-Null
        $row.Children.Add($s) | Out-Null
        $Stack.Children.Add($row) | Out-Null
    }

    Add-Slider '透明度' 'opacity' 0.03 1 1
    Add-Slider '宽度' 'width' 180 760 1
    Add-Slider '高度' 'height' 50 260 1
    Add-Slider '英文大小' 'wordSize' 12 60 1
    Add-Slider '释义大小' 'meaningSize' 9 34 1
    Add-Slider '轮播秒数' 'intervalMs' 1 60 1000

    $PresetRow = New-Object System.Windows.Controls.WrapPanel
    $PresetRow.Margin = '0,4,0,10'
    foreach ($preset in @(
        @{Text='白字清晰'; Word='#f8fafc'; Meaning='#e5e7eb'; Info='#cbd5e1'; Opacity=1.0; Shadow=$true},
        @{Text='黑字清晰'; Word='#111111'; Meaning='#222222'; Info='#555555'; Opacity=1.0; Shadow=$true},
        @{Text='灰字隐蔽'; Word='#9ca3af'; Meaning='#9ca3af'; Info='#9ca3af'; Opacity=0.96; Shadow=$false},
        @{Text='白字深底'; Word='#f8fafc'; Meaning='#e5e7eb'; Info='#cbd5e1'; Opacity=1.0; Shadow=$true},
        @{Text='高对比描边'; Word='#ffffff'; Meaning='#f1f5f9'; Info='#e2e8f0'; Opacity=1.0; Shadow=$true}
    )) {
        $b = New-Object System.Windows.Controls.Button
        $b.Content = $preset.Text
        $b.Margin = '0,0,8,6'
        $b.Tag = $preset
        $b.Add_Click({
            $p = $this.Tag
            $Settings.wordColor = $p.Word; $Settings.meaningColor = $p.Meaning; $Settings.infoColor = $p.Info; $Settings.opacity = $p.Opacity
            if ($p.Shadow -ne $null) { $Settings.textShadow = [bool]$p.Shadow }
            Apply-Visuals; Save-Settings
        })
        $PresetRow.Children.Add($b) | Out-Null
    }
    $Stack.Children.Add($PresetRow) | Out-Null

    $Combo = New-Object System.Windows.Controls.ComboBox
    $Combo.Margin = '0,0,0,10'
    foreach ($k in $Hotkeys.Keys) { $Combo.Items.Add($k) | Out-Null }
    $Combo.SelectedItem = $Settings.hotkey
    $Combo.Add_SelectionChanged({
        param($sender, $eventArgs)
        if ($sender.SelectedItem) { $Settings.hotkey = [string]$sender.SelectedItem; Register-Hotkey; Refresh-Word; Save-Settings }
    })
    $Stack.Children.Add((New-Object System.Windows.Controls.TextBlock -Property @{Text='手动下一词按键'})) | Out-Null
    $Stack.Children.Add($Combo) | Out-Null

    $FocusKeyRow = New-Object System.Windows.Controls.WrapPanel
    $FocusKeyRow.Margin = '0,0,0,10'

    $FocusFamiliarPanel = New-Object System.Windows.Controls.StackPanel
    $FocusFamiliarPanel.Width = 180
    $FocusFamiliarPanel.Margin = '0,0,12,0'
    $FocusFamiliarPanel.Children.Add((New-Object System.Windows.Controls.TextBlock -Property @{Text='专注熟悉键'})) | Out-Null
    $FocusFamiliarCombo = New-Object System.Windows.Controls.ComboBox
    foreach ($k in $FocusKeys) { $FocusFamiliarCombo.Items.Add($k) | Out-Null }
    $FocusFamiliarCombo.SelectedItem = [string]$Settings.focusFamiliarKey
    $FocusFamiliarCombo.Add_SelectionChanged({
        param($sender, $eventArgs)
        if ($sender.SelectedItem) {
            $Settings.focusFamiliarKey = [string]$sender.SelectedItem
            Refresh-Word
            Save-Settings
        }
    })
    $FocusFamiliarPanel.Children.Add($FocusFamiliarCombo) | Out-Null

    $FocusUnknownPanel = New-Object System.Windows.Controls.StackPanel
    $FocusUnknownPanel.Width = 180
    $FocusUnknownPanel.Children.Add((New-Object System.Windows.Controls.TextBlock -Property @{Text='专注生词键'})) | Out-Null
    $FocusUnknownCombo = New-Object System.Windows.Controls.ComboBox
    foreach ($k in $FocusKeys) { $FocusUnknownCombo.Items.Add($k) | Out-Null }
    $FocusUnknownCombo.SelectedItem = [string]$Settings.focusUnknownKey
    $FocusUnknownCombo.Add_SelectionChanged({
        param($sender, $eventArgs)
        if ($sender.SelectedItem) {
            $Settings.focusUnknownKey = [string]$sender.SelectedItem
            Refresh-Word
            Save-Settings
        }
    })
    $FocusUnknownPanel.Children.Add($FocusUnknownCombo) | Out-Null

    $FocusKeyRow.Children.Add($FocusFamiliarPanel) | Out-Null
    $FocusKeyRow.Children.Add($FocusUnknownPanel) | Out-Null
    $Stack.Children.Add($FocusKeyRow) | Out-Null

    $DeckCombo = New-Object System.Windows.Controls.ComboBox
    $DeckCombo.Margin = '0,0,0,10'
    foreach ($deck in @('全部','未分类','熟悉','生词')) { $DeckCombo.Items.Add($deck) | Out-Null }
    $DeckCombo.SelectedItem = [string]$Settings.studyDeck
    $DeckCombo.Add_SelectionChanged({
        param($sender, $eventArgs)
        if ($sender.SelectedItem) {
            try {
                $Settings.studyDeck = [string]$sender.SelectedItem
                Rebuild-StudyDeck
                Restore-StudyPosition
                Refresh-Word
                Schedule-Timer
                if ($script:StartBoxControl -is [System.Windows.Controls.TextBox]) {
                    $script:StartBoxControl.Text = [string]($Index + 1)
                    $script:StartHintControl.Text = "/ $($ActiveIndices.Count)"
                }
                Save-Settings
            } catch {
                [System.Windows.MessageBox]::Show("切换词库出错：`n$_", '错误') | Out-Null
            }
        }
    })
    $Stack.Children.Add((New-Object System.Windows.Controls.TextBlock -Property @{Text='本次背诵词库'})) | Out-Null
    $Stack.Children.Add($DeckCombo) | Out-Null

    $StartRow = New-Object System.Windows.Controls.WrapPanel
    $StartRow.Margin = '0,0,0,10'
    $StartRow.Children.Add((New-Object System.Windows.Controls.TextBlock -Property @{
        Text = '开始序号'
        Width = 70
        VerticalAlignment = 'Center'
    })) | Out-Null
    $StartBox = New-Object System.Windows.Controls.TextBox
    $script:StartBoxControl = $StartBox
    $StartBox.Width = 80
    $StartBox.Text = [string]($Index + 1)
    $StartBox.Margin = '0,0,8,0'
    $StartRow.Children.Add($StartBox) | Out-Null
    $StartHint = New-Object System.Windows.Controls.TextBlock
    $script:StartHintControl = $StartHint
    $StartHint.Text = "/ $($ActiveIndices.Count)"
    $StartHint.Width = 70
    $StartHint.VerticalAlignment = 'Center'
    $StartRow.Children.Add($StartHint) | Out-Null
    $StartButton = New-Object System.Windows.Controls.Button
    $StartButton.Content = '跳到这里'
    $StartButton.Add_Click({
        $raw = [string]$script:StartBoxControl.Text
        if ($raw -match '\d+') {
            $n = [int]$Matches[0]
            Jump-ToStudyNumber $n
            $script:StartBoxControl.Text = [string]($Index + 1)
            $script:StartHintControl.Text = "/ $($ActiveIndices.Count)"
        } else {
            $script:StartBoxControl.Text = [string]($Index + 1)
        }
    })
    $StartRow.Children.Add($StartButton) | Out-Null
    $Stack.Children.Add($StartRow) | Out-Null

    $ImportRow = New-Object System.Windows.Controls.WrapPanel
    $ImportRow.Margin = '0,0,0,10'
    $ImportFamiliarButton = New-Object System.Windows.Controls.Button
    $ImportFamiliarButton.Content = '导入熟悉词库 JSON'
    $ImportFamiliarButton.Margin = '0,0,8,6'
    $ImportFamiliarButton.Add_Click({ Import-WordSetFromDialog 'familiar' })
    $ImportRow.Children.Add($ImportFamiliarButton) | Out-Null

    $ImportUnknownButton = New-Object System.Windows.Controls.Button
    $ImportUnknownButton.Content = '导入生词库 JSON'
    $ImportUnknownButton.Margin = '0,0,8,6'
    $ImportUnknownButton.Add_Click({ Import-WordSetFromDialog 'unknown' })
    $ImportRow.Children.Add($ImportUnknownButton) | Out-Null
    $Stack.Children.Add($ImportRow) | Out-Null

    foreach ($pair in @(
        @('自动轮播','autoMode'), @('显示释义','showMeaning'), @('显示词性','showPos'),
        @('显示页码','showPage'), @('显示序号','showIndex'), @('显示模式','showMode'),
        @('窗口置顶','topmost'), @('清晰增强','textShadow'), @('淡背景辅助','backdrop'), @('随机顺序','randomOrder'), @('锁定位置','locked'),
        @('专注模式','focusMode')
    )) {
        $cb = New-Object System.Windows.Controls.CheckBox
        $cb.Content = $pair[0]
        $cb.IsChecked = [bool]$Settings[$pair[1]]
        $cb.Margin = '0,2,0,2'
        $cb.Tag = $pair[1]
        $cb.Add_Checked({
            param($sender, $eventArgs)
            $Settings[[string]$sender.Tag] = $true
            Apply-Visuals; Schedule-Timer; Save-Settings
        })
        $cb.Add_Unchecked({
            param($sender, $eventArgs)
            $Settings[[string]$sender.Tag] = $false
            Apply-Visuals; Schedule-Timer; Save-Settings
        })
        $Stack.Children.Add($cb) | Out-Null
    }

    $ButtonRow = New-Object System.Windows.Controls.WrapPanel
    $ButtonRow.Margin = '0,12,0,0'
    foreach ($spec in @(
        @{Text='词表目录'; Action={ Open-List }},
        @{Text='上一词'; Action={ Prev-Word }},
        @{Text='下一词'; Action={ Next-Word }},
        @{Text='退出'; Action={ $Window.Close() }}
    )) {
        $b = New-Object System.Windows.Controls.Button
        $b.Content = $spec.Text
        $b.Margin = '0,0,8,6'
        $act = $spec.Action
        $b.Add_Click($act)
        $ButtonRow.Children.Add($b) | Out-Null
    }
    $Stack.Children.Add($ButtonRow) | Out-Null
    $SettingsWindow.Show() | Out-Null
}

$Timer.Add_Tick({ Next-Word })
$WheelTimer.Interval = [TimeSpan]::FromMilliseconds(55)
$WheelTimer.Add_Tick({
    $WheelTimer.Stop()
    if ($script:WheelDelta -gt 0) {
        $script:WheelDelta = 0
        Prev-Word
    } elseif ($script:WheelDelta -lt 0) {
        $script:WheelDelta = 0
        Next-Word
    }
})

$Window.Add_MouseLeftButtonDown({
    $Window.Activate() | Out-Null
    $Window.Focus() | Out-Null
    if ($Settings.focusMode) {
        Mark-CurrentWord 'familiar'
        return
    }
    $script:IsPointerDown = $true
    $script:IsDragging = $false
    $script:DragStartPoint = $_.GetPosition($Window)
    $script:DragWindowLeft = [double]$Window.Left
    $script:DragWindowTop = [double]$Window.Top
    $script:DragStartSource = $_.OriginalSource
    $Window.CaptureMouse() | Out-Null
    $_.Handled = $true
})
$Window.Add_MouseMove({
    if (-not $script:IsPointerDown -or $Settings.locked) { return }
    $point = $_.GetPosition($Window)
    $dx = $point.X - $script:DragStartPoint.X
    $dy = $point.Y - $script:DragStartPoint.Y
    if (-not $script:IsDragging -and ([Math]::Abs($dx) -gt 3 -or [Math]::Abs($dy) -gt 3)) {
        $script:IsDragging = $true
    }
    if ($script:IsDragging) {
        $Window.Left = $script:DragWindowLeft + $dx
        $Window.Top = $script:DragWindowTop + $dy
        $_.Handled = $true
    }
})
$Window.Add_MouseLeftButtonUp({
    if ($Settings.focusMode) { return }
    $wasDragging = $script:IsDragging
    $startSource = $script:DragStartSource
    $script:IsPointerDown = $false
    $script:IsDragging = $false
    $script:DragStartPoint = $null
    $script:DragStartSource = $null
    $Window.ReleaseMouseCapture()
    if (-not $wasDragging) {
        if ($_.ClickCount -ge 2) {
            Next-Word
        } else {
            Open-Settings
        }
    }
    $_.Handled = $true
})
$Window.Add_MouseRightButtonUp({
    if ($Settings.focusMode) {
        Mark-CurrentWord 'unknown'
        return
    }
    Open-Settings
})
$Window.Add_MouseWheel({
    Queue-Wheel $_.Delta
    $_.Handled = $true
})
$Window.Add_PreviewKeyDown({
    if (Handle-AppKey ([string]$_.Key)) {
        $_.Handled = $true
    }
})
$Window.Add_LocationChanged({
    $Settings.x = [int]$Window.Left
    $Settings.y = [int]$Window.Top
    $SaveTimer.Stop()
    $SaveTimer.Start()
})
$Window.Add_Closed({
    if ($Source) { [HotKeyNative]::UnregisterHotKey($Source.Handle, $HotKeyId) | Out-Null }
    Save-Settings
})
$Window.Add_SourceInitialized({
    $script:Source = [System.Windows.Interop.HwndSource]::FromHwnd((New-Object System.Windows.Interop.WindowInteropHelper($Window)).Handle)
    $script:Source.AddHook({
        param($hwnd, $msg, $wParam, $lParam, [ref]$handled)
        if ($msg -eq 0x0312 -and $wParam.ToInt32() -eq $HotKeyId) {
            Next-Word
            $handled.Value = $true
        }
        return [IntPtr]::Zero
    }) | Out-Null
    Register-Hotkey
})
$Window.Add_Loaded({
    $Window.Activate() | Out-Null
    $Window.Focus() | Out-Null
})

Rebuild-StudyDeck
Restore-StudyPosition
Apply-Visuals
Schedule-Timer
$Window.ShowDialog() | Out-Null
