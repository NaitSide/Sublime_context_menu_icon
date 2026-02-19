@echo off
chcp 65001 >nul

:: Самоэлевация прав администратора
net session >nul 2>&1
if %errorlevel% neq 0 (
    cls
    echo.
    echo =========================================================
    echo    [ОШИБКА] Требуются права администратора!
    echo =========================================================
    echo.
    echo    Запустите скрипт правой кнопкой мыши
    echo    -^> "Запуск от имени администратора"
    echo.
    echo =========================================================
    echo.
    pause
    exit /b
)

:MENU
cls
echo =========================================================
echo   Sublime Text - Context menu icon
echo   NaitSide Tools
echo =========================================================
echo.
echo  Выберите действие:
echo.
echo  [1] - Русский     "Открыть в Sublime Text"
echo  [2] - English     "Open with Sublime Text"
echo  [3] - Вернуть стандартное поведение Sublime
echo  [4] - Удалить иконки и вернуть все настройки
echo  [0] - Выход
echo.
echo =========================================================
echo    GitHub: github.com/NaitSide
echo =========================================================
echo.
set /p choice="Ваш выбор: "
if "%choice%"=="1" goto RUSSIAN
if "%choice%"=="2" goto ENGLISH
if "%choice%"=="3" goto SETTINGS_RESET
if "%choice%"=="4" goto FULL_RESET
if "%choice%"=="0" exit
goto MENU

:RUSSIAN
set "MENU_LABEL=Открыть в Sublime Text"
goto APPLY

:ENGLISH
set "MENU_LABEL=Open with Sublime Text"
goto APPLY

:APPLY
cls
echo =========================================================
echo   Sublime Text - Context menu icon
echo   NaitSide Tools
echo =========================================================
echo.

set "SUBLIME_PATH=C:\Program Files\Sublime Text\sublime_text.exe"

if not exist "%SUBLIME_PATH%" (
    echo    [ОШИБКА] Sublime Text не найден по пути:
    echo    %SUBLIME_PATH%
    echo.
    echo    Проверьте путь установки и повторите.
    echo.
    pause
    goto MENU
)

echo    Путь к Sublime Text: %SUBLIME_PATH%
echo    Пункт меню: %MENU_LABEL%
echo.

:: Удаление старых записей
echo    Удаление старых записей...
reg delete "HKEY_CLASSES_ROOT\*\shell\Open with Sublime Text" /f >nul 2>&1
reg delete "HKEY_CLASSES_ROOT\*\shell\Открыть в Sublime Text" /f >nul 2>&1
reg delete "HKEY_CLASSES_ROOT\Directory\shell\Open with Sublime Text" /f >nul 2>&1
reg delete "HKEY_CLASSES_ROOT\Directory\shell\Открыть в Sublime Text" /f >nul 2>&1
reg delete "HKEY_CLASSES_ROOT\Directory\Background\shell\Open with Sublime Text" /f >nul 2>&1
reg delete "HKEY_CLASSES_ROOT\Directory\Background\shell\Открыть в Sublime Text" /f >nul 2>&1
echo    [OK] Старые записи удалены

echo.
echo    Добавление новых записей...

:: Файлы
reg add "HKEY_CLASSES_ROOT\*\shell\%MENU_LABEL%" /ve /t REG_SZ /d "%MENU_LABEL%" /f >nul 2>&1
reg add "HKEY_CLASSES_ROOT\*\shell\%MENU_LABEL%" /v "Icon" /t REG_SZ /d "%SUBLIME_PATH%,0" /f >nul 2>&1
reg add "HKEY_CLASSES_ROOT\*\shell\%MENU_LABEL%\command" /ve /t REG_SZ /d "%SUBLIME_PATH% \"%%1\"" /f >nul 2>&1
echo    [OK] Добавлена иконка в контекстное меню файлов

:: Папки
reg add "HKEY_CLASSES_ROOT\Directory\shell\%MENU_LABEL%" /ve /t REG_SZ /d "%MENU_LABEL%" /f >nul 2>&1
reg add "HKEY_CLASSES_ROOT\Directory\shell\%MENU_LABEL%" /v "Icon" /t REG_SZ /d "%SUBLIME_PATH%,0" /f >nul 2>&1
reg add "HKEY_CLASSES_ROOT\Directory\shell\%MENU_LABEL%\command" /ve /t REG_SZ /d "%SUBLIME_PATH% \"%%1\"" /f >nul 2>&1
echo    [OK] Добавлена иконка в контекстное меню папок

:: Правый клик по пустому месту в папке
reg add "HKEY_CLASSES_ROOT\Directory\Background\shell\%MENU_LABEL%" /ve /t REG_SZ /d "%MENU_LABEL%" /f >nul 2>&1
reg add "HKEY_CLASSES_ROOT\Directory\Background\shell\%MENU_LABEL%" /v "Icon" /t REG_SZ /d "%SUBLIME_PATH%,0" /f >nul 2>&1
reg add "HKEY_CLASSES_ROOT\Directory\Background\shell\%MENU_LABEL%\command" /ve /t REG_SZ /d "%SUBLIME_PATH% \"%%V\"" /f >nul 2>&1
echo    [OK] Добавлена иконка - правый клик по пустому месту в папке

echo.
echo    Применение настроек Sublime...
call :DO_SETTINGS_APPLY
echo    [OK] Настройки сессии отключены

echo.
echo =========================================================
echo    Готово! Пункт "%MENU_LABEL%" добавлен.
echo =========================================================
echo.
pause
goto MENU

:SETTINGS_RESET
cls
echo =========================================================
echo   Sublime Text - Context menu icon
echo   NaitSide Tools
echo =========================================================
echo.
echo  Будут возвращены стандартные настройки Sublime:
echo.
echo  hot_exit: true
echo  - При закрытии Sublime сохраняет сессию.
echo  - Несохранённые файлы восстанавливаются при запуске.
echo.
echo  remember_open_files: true
echo  - При запуске восстанавливаются все открытые файлы.
echo.
echo =========================================================
echo.
set /p confirm="Вернуть стандартное поведение? (Y/N): "
if /i "%confirm%"=="Y" goto DO_SETTINGS_RESET
goto MENU

:FULL_RESET
cls
echo =========================================================
echo   Sublime Text - Context menu icon
echo   NaitSide Tools
echo =========================================================
echo.
echo  Будет выполнено:
echo.
echo  - Удаление всех записей из контекстного меню
echo  - Возврат стандартных настроек Sublime
echo.
echo =========================================================
echo.
set /p confirm="Продолжить? (Y/N): "
if /i not "%confirm%"=="Y" goto MENU

echo.
echo    Удаление записей из контекстного меню...
reg delete "HKEY_CLASSES_ROOT\*\shell\Open with Sublime Text" /f >nul 2>&1
reg delete "HKEY_CLASSES_ROOT\*\shell\Открыть в Sublime Text" /f >nul 2>&1
reg delete "HKEY_CLASSES_ROOT\Directory\shell\Open with Sublime Text" /f >nul 2>&1
reg delete "HKEY_CLASSES_ROOT\Directory\shell\Открыть в Sublime Text" /f >nul 2>&1
reg delete "HKEY_CLASSES_ROOT\Directory\Background\shell\Open with Sublime Text" /f >nul 2>&1
reg delete "HKEY_CLASSES_ROOT\Directory\Background\shell\Открыть в Sublime Text" /f >nul 2>&1
echo    [OK] Записи удалены

echo.
echo    Возврат стандартных настроек Sublime...
call :DO_SETTINGS_RESET_SILENT
echo    [OK] Настройки восстановлены

echo.
echo =========================================================
echo    Готово! Все изменения отменены.
echo =========================================================
echo.
pause
goto MENU

:DO_SETTINGS_APPLY
set "SETTINGS_PATH=%APPDATA%\Sublime Text\Packages\User\Preferences.sublime-settings"
set "PS_TEMP=%TEMP%\sublime_fix.ps1"
if not exist "%SETTINGS_PATH%" echo { > "%SETTINGS_PATH%"
if not exist "%SETTINGS_PATH%" echo } >> "%SETTINGS_PATH%"
echo $p = "$env:APPDATA\Sublime Text\Packages\User\Preferences.sublime-settings" > "%PS_TEMP%"
echo $lines = Get-Content $p >> "%PS_TEMP%"
echo $clean = ($lines ^| Where-Object { $_ -notmatch '^\s*//' }) -join [Environment]::NewLine >> "%PS_TEMP%"
echo $j = $clean ^| ConvertFrom-Json >> "%PS_TEMP%"
echo $j ^| Add-Member -Force -NotePropertyName 'hot_exit' -NotePropertyValue $false >> "%PS_TEMP%"
echo $j ^| Add-Member -Force -NotePropertyName 'remember_open_files' -NotePropertyValue $false >> "%PS_TEMP%"
echo $j ^| ConvertTo-Json -Depth 10 ^| Set-Content $p >> "%PS_TEMP%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_TEMP%"
del "%PS_TEMP%" >nul 2>&1
goto :EOF

:DO_SETTINGS_RESET
set "SETTINGS_PATH=%APPDATA%\Sublime Text\Packages\User\Preferences.sublime-settings"
if not exist "%SETTINGS_PATH%" (
    echo.
    echo    [--] Файл настроек не найден. Ничего не изменено.
    echo.
    pause
    goto MENU
)
set "PS_TEMP=%TEMP%\sublime_fix.ps1"
echo $p = "$env:APPDATA\Sublime Text\Packages\User\Preferences.sublime-settings" > "%PS_TEMP%"
echo $lines = Get-Content $p >> "%PS_TEMP%"
echo $clean = ($lines ^| Where-Object { $_ -notmatch '^\s*//' }) -join [Environment]::NewLine >> "%PS_TEMP%"
echo $j = $clean ^| ConvertFrom-Json >> "%PS_TEMP%"
echo $j.PSObject.Properties.Remove('hot_exit'^) >> "%PS_TEMP%"
echo $j.PSObject.Properties.Remove('remember_open_files'^) >> "%PS_TEMP%"
echo $j ^| ConvertTo-Json -Depth 10 ^| Set-Content $p >> "%PS_TEMP%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_TEMP%"
del "%PS_TEMP%" >nul 2>&1
echo.
echo    [OK] Стандартное поведение восстановлено.
echo.
pause
goto MENU

:DO_SETTINGS_RESET_SILENT
set "SETTINGS_PATH=%APPDATA%\Sublime Text\Packages\User\Preferences.sublime-settings"
if not exist "%SETTINGS_PATH%" goto :EOF
set "PS_TEMP=%TEMP%\sublime_fix.ps1"
echo $p = "$env:APPDATA\Sublime Text\Packages\User\Preferences.sublime-settings" > "%PS_TEMP%"
echo $lines = Get-Content $p >> "%PS_TEMP%"
echo $clean = ($lines ^| Where-Object { $_ -notmatch '^\s*//' }) -join [Environment]::NewLine >> "%PS_TEMP%"
echo $j = $clean ^| ConvertFrom-Json >> "%PS_TEMP%"
echo $j.PSObject.Properties.Remove('hot_exit'^) >> "%PS_TEMP%"
echo $j.PSObject.Properties.Remove('remember_open_files'^) >> "%PS_TEMP%"
echo $j ^| ConvertTo-Json -Depth 10 ^| Set-Content $p >> "%PS_TEMP%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_TEMP%"
del "%PS_TEMP%" >nul 2>&1
goto :EOF