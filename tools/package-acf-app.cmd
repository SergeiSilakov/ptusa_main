@echo off
rem Упаковка приложения ACF (*.app) для AXC F 2000 EA.
rem
rem Применение:
rem     tools\package-acf-app.cmd [конфигурация] [версия] ["аргументы запуска"] [адрес контроллера]
rem
rem Примеры:
rem     tools\package-acf-app.cmd
rem     tools\package-acf-app.cmd Debug 1.0.2
rem     tools\package-acf-app.cmd Debug 1.0.2 "-d main.plua"
rem     tools\package-acf-app.cmd Release 1.0.3 "" 192.0.2.10
rem
rem Адрес контроллера: если не задан аргументом, берётся из
rem tools\local-settings.cmake, затем из IOL_HOST.
rem
rem Параметры подключения (в репозиторий не попадают):
rem     IOL_SDK         каталог PLCnext SDK
rem     IOL_HOST        адрес контроллера
rem     IOL_SSH_KEY     ключ PuTTY (*.ppk)
rem     IOL_SSH/IOL_SCP команды целиком (переопределяют HOST/KEY)
rem     IOL_IDENTIFIER  идентификатор приложения (14 цифр)
rem     IOL_EXEC_ARGS   аргументы запуска в quadlet
rem     IOL_DRYRUN=1    сухой прогон (ssh/scp = echo)
rem
rem Из Visual Studio: цель CMake "acf_package" в CMake Targets View
rem (адрес — переменная PTUSA_APP_HOST пресета/кэша).
rem
rem Из консоли CMake:
rem     cmake --build --preset build-windows-AXCF2000EA-2026-LTS-Debug --target acf_package

setlocal
set "CFG=%~1"
if "%CFG%"=="" set "CFG=Debug"
set "VER=%~2"
if "%VER%"=="" set "VER=1.0.2"

set "EXTRA="
if not "%~3"=="" set "EXTRA=-DEXEC_ARGS=%~3"
if not "%~4"=="" set "EXTRA2=-DHOST=%~4"

cmake "-DCFG=%CFG%" "-DVERSION=%VER%" %EXTRA% %EXTRA2% -P "%~dp0package-acf-app.cmake"
exit /b %ERRORLEVEL%
