@echo off
chcp 65001 >nul
rem 水村山郭啟動器：找到 Godot 4.6 並開啟本專案。三個入口（開始遊戲、開發模式、開啟編輯器）都呼叫這裡。
rem 用法：launch.cmd [game^|dev^|editor]
rem 找 Godot 的順序：環境變數 GODOT、遊戲資料夾或上一層的 Godot*.exe、PATH 上的 godot、舊機器路徑、WSL 裡的 Linux 版。
rem 先切成 UTF-8 再寫中文：中文版 Windows 預設以 GBK 讀批次檔，切換前的中文行可能吞掉換行。
setlocal

rem 專案根目錄（本檔在 scripts\tools 下）。不用 cd：專案放在 \\wsl.localhost 這類網路路徑時，cmd 無法以它為工作目錄
set "PROJ=%~dp0..\.."
for %%I in ("%PROJ%") do set "PROJ=%%~fI"

set "MODE=%~1"
set "GARGS="
set "UARGS="
if /i "%MODE%"=="dev" set "UARGS=-- --dev --city=auto"
if /i "%MODE%"=="editor" set "GARGS=--editor"

rem 1. 環境變數 GODOT
if defined GODOT if exist "%GODOT%" goto run_win
set "GODOT="

rem 2. 遊戲資料夾或上一層資料夾裡的 Godot*.exe（把下載的 Godot 放在旁邊即可）
for %%D in ("%PROJ%" "%PROJ%\..") do (
	for %%F in ("%%~fD\Godot*.exe") do (
		if not defined GODOT set "GODOT=%%~fF"
	)
)
if defined GODOT goto run_win

rem 3. PATH 上的 godot
for %%N in (godot.exe godot4.exe) do (
	for /f "delims=" %%P in ('where %%N 2^>nul') do (
		if not defined GODOT set "GODOT=%%P"
	)
)
if defined GODOT goto run_win

rem 4. 舊機器上的路徑
set "OLD=D:\zoo\.tools\godot\4.6.1\Godot_v4.6.1-stable_mono_win64\Godot_v4.6.1-stable_mono_win64.exe"
if exist "%OLD%" (
	set "GODOT=%OLD%"
	goto run_win
)

rem 5. 專案在 WSL 裡：用 WSL 的 Linux 版 Godot（WSLg 開窗，D3D12 走顯卡）
where wsl.exe >nul 2>nul
if not errorlevel 1 if exist "%PROJ%\..\..\.toolchains\godot\4.6.1\Godot_v4.6.1-stable_linux.x86_64" goto run_wsl

echo.
echo   找不到 Godot 4.6。
echo.
echo   請到 https://godotengine.org/download/archive/4.6.1-stable/ 下載 Windows 版，
echo   解壓後把 Godot_v4.6.1-stable_win64.exe 放進遊戲資料夾（或上一層），再雙擊一次即可。
echo   也可以設定環境變數 GODOT，指向 Godot 程式的完整路徑。
echo.
pause
exit /b 1

:run_win
start "" "%GODOT%" %GARGS% --path "%PROJ%" %UARGS%
exit /b 0

:run_wsl
start "" /min wsl.exe --cd "%PROJ%" -e bash -lc "GALLIUM_DRIVER=d3d12 MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA ../../.toolchains/godot/4.6.1/Godot_v4.6.1-stable_linux.x86_64 %GARGS% --path . %UARGS%"
exit /b 0
