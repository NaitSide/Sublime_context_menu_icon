# Self-elevation: если нет прав админа — перезапустить с UAC
# ВАЖНО: блок стоит самым первым исполняемым кодом, как в рабочем AutoLogin_Enable.ps1.
# Unblock-File нужен, чтобы после первого предупреждения Windows не показывала второе
# такое же предупреждение уже в повышенном PowerShell.
$scriptPath = $PSCommandPath
if ([string]::IsNullOrWhiteSpace($scriptPath)) {
    $scriptPath = $MyInvocation.MyCommand.Path
}

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try { Unblock-File -LiteralPath $scriptPath -ErrorAction SilentlyContinue } catch {}
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$scriptPath`""
    exit
}

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$SUBLIME_PATH  = 'C:\Program Files\Sublime Text\sublime_text.exe'
$SETTINGS_PATH = Join-Path $env:APPDATA 'Sublime Text\Packages\User\Preferences.sublime-settings'

$MENU_LABEL_RU = 'Открыть в Sublime Text'
$MENU_LABEL_EN = 'Open with Sublime Text'

function Add-Log {
    param([string]$Text)
    $txtLog.AppendText("$Text`r`n")
    $txtLog.SelectionStart = $txtLog.TextLength
    $txtLog.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Get-ClassesRootWritable {
    return [Microsoft.Win32.Registry]::ClassesRoot
}

function Remove-ContextMenuEntries {
    $root = Get-ClassesRootWritable
    $subKeys = @(
        "*\shell\$MENU_LABEL_RU",
        "*\shell\$MENU_LABEL_EN",
        "Directory\shell\$MENU_LABEL_RU",
        "Directory\shell\$MENU_LABEL_EN",
        "Directory\Background\shell\$MENU_LABEL_RU",
        "Directory\Background\shell\$MENU_LABEL_EN"
    )

    foreach ($subKey in $subKeys) {
        try {
            $root.DeleteSubKeyTree($subKey, $false)
            Add-Log "[OK] Удалено: HKCR\$subKey"
        }
        catch {
            Add-Log "[!!] Не удалось удалить HKCR\$subKey : $($_.Exception.Message)"
        }
    }
}

function New-ContextMenuEntry {
    param(
        [Parameter(Mandatory = $true)] [string] $SubKeyPath,
        [Parameter(Mandatory = $true)] [string] $CommandValue,
        [Parameter(Mandatory = $true)] [string] $Label
    )

    $root = Get-ClassesRootWritable
    $shellKey = $root.CreateSubKey($SubKeyPath)
    if ($null -eq $shellKey) { throw "Не удалось создать HKCR\$SubKeyPath" }

    $shellKey.SetValue('MUIVerb', $Label, [Microsoft.Win32.RegistryValueKind]::String)
    $shellKey.SetValue('Icon', "$SUBLIME_PATH,0", [Microsoft.Win32.RegistryValueKind]::String)

    $commandKey = $shellKey.CreateSubKey('command')
    if ($null -eq $commandKey) { throw "Не удалось создать HKCR\$SubKeyPath\command" }

    $commandKey.SetValue('', $CommandValue, [Microsoft.Win32.RegistryValueKind]::String)
    $commandKey.Close()
    $shellKey.Close()
}

function Ensure-SublimeSettingsFile {
    $settingsDir = Split-Path $SETTINGS_PATH -Parent
    if (-not (Test-Path $settingsDir)) {
        New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    }
    if (-not (Test-Path $SETTINGS_PATH)) {
        Set-Content -Path $SETTINGS_PATH -Value "{`r`n}`r`n" -Encoding UTF8
    }
}

function Repair-SublimeSettingsRaw {
    param([string]$Raw)

    if ([string]::IsNullOrWhiteSpace($Raw)) {
        return "{`r`n}`r`n"
    }

    # Нормализуем переносы строк.
    $Raw = $Raw -replace "`r?`n", "`r`n"

    # Чиним старый баг вида: }//{
    # Он появлялся, когда старый патчер склеивал два объекта настроек подряд.
    $Raw = [regex]::Replace($Raw, "(?s)\}\s*//\s*\{", ",`r`n")

    # Убираем случайно закомментированные одиночные фигурные скобки старого патчера.
    # ВАЖНО: обычные { и } не трогаем.
    $Raw = [regex]::Replace($Raw, "(?m)^\s*//\s*\{\s*`r?`n", '')
    $Raw = [regex]::Replace($Raw, "(?m)^\s*//\s*\}\s*`r?`n", '')

    $trimmed = $Raw.Trim()

    # Если файл после старой поломки остался без обертки — возвращаем объект.
    if (-not $trimmed.StartsWith('{')) {
        $trimmed = "{`r`n" + $trimmed
    }
    if (-not $trimmed.EndsWith('}')) {
        $trimmed = $trimmed.TrimEnd(',') + "`r`n}"
    }

    return $trimmed + "`r`n"
}

function Remove-ManagedSettingLines {
    param([string]$Raw)

    # Удаляем ВСЕ строки, которыми управляет скрипт.
    # Важно: прежний шаблон был ошибочный: //? требовал минимум один slash,
    # поэтому обычные строки без // не удалялись и появлялись дубликаты.
    # Этот шаблон удаляет и активные строки, и закомментированные варианты:
    #     "hot_exit": false,
    #     //"hot_exit": false,
    #     // "hot_exit": false,
    foreach ($name in @('hot_exit', 'remember_open_files')) {
        $escapedName = [regex]::Escape($name)
        $pattern = '(?m)^\s*(?://\s*)?"' + $escapedName + '"\s*:\s*(?:true|false)\s*,?\s*(?:\r?\n|$)'
        $Raw = [regex]::Replace($Raw, $pattern, '')
    }

    return $Raw
}

function Set-SublimeManagedSettings {
    param(
        [string]$Raw,
        [bool]$Enabled
    )

    # Enabled = true  -> фикс включен: false / false
    # Enabled = false -> стандартное поведение Sublime: true / true
    $valueText = if ($Enabled) { 'false' } else { 'true' }

    $Raw = Repair-SublimeSettingsRaw -Raw $Raw
    $Raw = Remove-ManagedSettingLines -Raw $Raw

    $trimmed = $Raw.TrimEnd()
    $lastBrace = $trimmed.LastIndexOf('}')

    if ($lastBrace -lt 0) {
        return "{`r`n    `"hot_exit`": $valueText,`r`n    `"remember_open_files`": $valueText`r`n}`r`n"
    }

    $beforeClose = $trimmed.Substring(0, $lastBrace).TrimEnd()
    $afterOpenClean = $beforeClose.Trim()

    # Пустой объект: просто вставляем две строки без ведущей запятой.
    if ($afterOpenClean -eq '{') {
        return "{`r`n    `"hot_exit`": $valueText,`r`n    `"remember_open_files`": $valueText`r`n}`r`n"
    }

    # Если перед вставкой последняя активная настройка без запятой — добавляем запятую.
    # Не допускаем строку вида
    # "show_line_endings": true
    # "hot_exit": false
    if (-not $beforeClose.EndsWith(',')) {
        $beforeClose = $beforeClose + ','
    }

    return $beforeClose + "`r`n    `"hot_exit`": $valueText,`r`n    `"remember_open_files`": $valueText`r`n}`r`n"
}

function Add-SublimeManagedSettings {
    param([string]$Raw)
    return Set-SublimeManagedSettings -Raw $Raw -Enabled $true
}

function Reset-SublimeManagedSettings {
    param([string]$Raw)
    return Set-SublimeManagedSettings -Raw $Raw -Enabled $false
}

function Apply-SublimeSettings {
    Ensure-SublimeSettingsFile

    $backupPath = "$SETTINGS_PATH.bak_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')"
    Copy-Item -Path $SETTINGS_PATH -Destination $backupPath -Force
    Add-Log "[OK] Бэкап настроек: $backupPath"

    $raw = Get-Content -Path $SETTINGS_PATH -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { $raw = "{`r`n}`r`n" }

    $raw = Add-SublimeManagedSettings -Raw $raw

    Set-Content -Path $SETTINGS_PATH -Value $raw -Encoding UTF8
    Add-Log '[OK] Настройки Sublime обновлены'
}

function Reset-SublimeSettings {
    if (-not (Test-Path $SETTINGS_PATH)) {
        Add-Log '[--] Файл настроек Sublime не найден'
        return
    }

    $backupPath = "$SETTINGS_PATH.bak_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')"
    Copy-Item -Path $SETTINGS_PATH -Destination $backupPath -Force
    Add-Log "[OK] Бэкап настроек: $backupPath"

    $raw = Get-Content -Path $SETTINGS_PATH -Raw -Encoding UTF8
    $raw = Reset-SublimeManagedSettings -Raw $raw

    Set-Content -Path $SETTINGS_PATH -Value $raw -Encoding UTF8
    Add-Log '[OK] Стандартное поведение Sublime восстановлено'
}

function Apply-ContextMenu {
    param([string]$Label)

    $txtLog.Clear()
    Add-Log 'Старт...'
    Add-Log "Sublime: $SUBLIME_PATH"
    Add-Log "Пункт меню: $Label"

    if (-not (Test-Path $SUBLIME_PATH)) {
        throw "Sublime Text не найден по пути: $SUBLIME_PATH"
    }

    Add-Log 'Удаление старых записей...'
    Remove-ContextMenuEntries

    Add-Log 'Добавление новых записей...'
    New-ContextMenuEntry -SubKeyPath "*\shell\$Label" -CommandValue "`"$SUBLIME_PATH`" `"%1`"" -Label $Label
    Add-Log '[OK] Добавлено для файлов'

    New-ContextMenuEntry -SubKeyPath "Directory\shell\$Label" -CommandValue "`"$SUBLIME_PATH`" `"%1`"" -Label $Label
    Add-Log '[OK] Добавлено для папок'

    New-ContextMenuEntry -SubKeyPath "Directory\Background\shell\$Label" -CommandValue "`"$SUBLIME_PATH`" `"%V`"" -Label $Label
    Add-Log '[OK] Добавлено для пустого места внутри папки'

    Add-Log 'Применение настроек Sublime...'
    Apply-SublimeSettings

    Add-Log 'Готово.'
    [System.Windows.Forms.MessageBox]::Show("Пункт меню `"$Label`" добавлен.", 'Готово', 'OK', 'Information') | Out-Null
}

function Do-SafeAction {
    param([scriptblock]$Action)
    try {
        & $Action
    }
    catch {
        Add-Log "[ERROR] $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Ошибка', 'OK', 'Error') | Out-Null
    }
}

# ---------- GUI ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Sublime Text — Context Menu Icon | NaitSide Tools'
$form.Size = New-Object System.Drawing.Size(620, 430)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 40)
$form.ForeColor = [System.Drawing.Color]::White

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = 'Sublime Text — контекстное меню'
$lblTitle.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(160, 130, 255)
$lblTitle.Location = New-Object System.Drawing.Point(20, 16)
$lblTitle.Size = New-Object System.Drawing.Size(560, 26)
$form.Controls.Add($lblTitle)

$lblInfo = New-Object System.Windows.Forms.Label
$lblInfo.Text = 'Добавляет пункт открытия файлов/папок в Sublime Text и правит поведение hot_exit.'
$lblInfo.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$lblInfo.Location = New-Object System.Drawing.Point(20, 48)
$lblInfo.Size = New-Object System.Drawing.Size(560, 22)
$form.Controls.Add($lblInfo)

$btnRu = New-Object System.Windows.Forms.Button
$btnRu.Text = 'Добавить: Открыть в Sublime Text'
$btnRu.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
$btnRu.Location = New-Object System.Drawing.Point(20, 86)
$btnRu.Size = New-Object System.Drawing.Size(270, 38)
$btnRu.BackColor = [System.Drawing.Color]::FromArgb(100, 70, 200)
$btnRu.ForeColor = [System.Drawing.Color]::White
$btnRu.FlatStyle = 'Flat'
$btnRu.FlatAppearance.BorderSize = 0
$form.Controls.Add($btnRu)

$btnEn = New-Object System.Windows.Forms.Button
$btnEn.Text = 'Добавить: Open with Sublime Text'
$btnEn.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$btnEn.Location = New-Object System.Drawing.Point(314, 86)
$btnEn.Size = New-Object System.Drawing.Size(270, 38)
$btnEn.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 75)
$btnEn.ForeColor = [System.Drawing.Color]::White
$btnEn.FlatStyle = 'Flat'
$btnEn.FlatAppearance.BorderSize = 0
$form.Controls.Add($btnEn)

$btnResetSettings = New-Object System.Windows.Forms.Button
$btnResetSettings.Text = 'Вернуть стандартное поведение Sublime'
$btnResetSettings.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$btnResetSettings.Location = New-Object System.Drawing.Point(20, 136)
$btnResetSettings.Size = New-Object System.Drawing.Size(270, 34)
$btnResetSettings.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 75)
$btnResetSettings.ForeColor = [System.Drawing.Color]::White
$btnResetSettings.FlatStyle = 'Flat'
$btnResetSettings.FlatAppearance.BorderSize = 0
$form.Controls.Add($btnResetSettings)

$btnFullReset = New-Object System.Windows.Forms.Button
$btnFullReset.Text = 'Удалить пункт меню и настройки'
$btnFullReset.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$btnFullReset.Location = New-Object System.Drawing.Point(314, 136)
$btnFullReset.Size = New-Object System.Drawing.Size(270, 34)
$btnFullReset.BackColor = [System.Drawing.Color]::FromArgb(80, 55, 55)
$btnFullReset.ForeColor = [System.Drawing.Color]::White
$btnFullReset.FlatStyle = 'Flat'
$btnFullReset.FlatAppearance.BorderSize = 0
$form.Controls.Add($btnFullReset)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$txtLog.Location = New-Object System.Drawing.Point(20, 188)
$txtLog.Size = New-Object System.Drawing.Size(564, 150)
$txtLog.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 28)
$txtLog.ForeColor = [System.Drawing.Color]::FromArgb(220, 220, 230)
$form.Controls.Add($txtLog)

$lblFooter = New-Object System.Windows.Forms.Label
$lblFooter.Text = 'github.com/NaitSide'
$lblFooter.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$lblFooter.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 120)
$lblFooter.Location = New-Object System.Drawing.Point(20, 354)
$lblFooter.Size = New-Object System.Drawing.Size(250, 20)
$form.Controls.Add($lblFooter)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = 'Закрыть'
$btnClose.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$btnClose.Location = New-Object System.Drawing.Point(464, 348)
$btnClose.Size = New-Object System.Drawing.Size(120, 32)
$btnClose.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 75)
$btnClose.ForeColor = [System.Drawing.Color]::White
$btnClose.FlatStyle = 'Flat'
$btnClose.FlatAppearance.BorderSize = 0
$form.Controls.Add($btnClose)

$btnRu.Add_Click({ Do-SafeAction { Apply-ContextMenu $MENU_LABEL_RU } })
$btnEn.Add_Click({ Do-SafeAction { Apply-ContextMenu $MENU_LABEL_EN } })
$btnResetSettings.Add_Click({
    Do-SafeAction {
        $txtLog.Clear()
        Reset-SublimeSettings
        [System.Windows.Forms.MessageBox]::Show('Стандартное поведение Sublime восстановлено.', 'Готово', 'OK', 'Information') | Out-Null
    }
})
$btnFullReset.Add_Click({
    $answer = [System.Windows.Forms.MessageBox]::Show('Удалить записи контекстного меню и вернуть настройки Sublime?', 'Подтверждение', 'YesNo', 'Question')
    if ($answer -eq 'Yes') {
        Do-SafeAction {
            $txtLog.Clear()
            Add-Log 'Удаление записей контекстного меню...'
            Remove-ContextMenuEntries
            Add-Log 'Возврат настроек Sublime...'
            Reset-SublimeSettings
            Add-Log 'Готово.'
            [System.Windows.Forms.MessageBox]::Show('Все изменения отменены.', 'Готово', 'OK', 'Information') | Out-Null
        }
    }
})
$btnClose.Add_Click({ $form.Close() })

Add-Log 'Готов к работе.'
[void]$form.ShowDialog()
