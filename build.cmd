@echo off
setlocal
rem Double-click to build XCross Studio (Windows release) into dist\studio-windows
set "ROOT=%~dp0"
for /f "usebackq delims=" %%P in (`powershell -NoProfile -Command "[Environment]::GetEnvironmentVariable('Path','Machine')+';'+[Environment]::GetEnvironmentVariable('Path','User')"`) do set "PATH=%%P"
pushd "%ROOT%apps\studio" || goto :fail
call flutter build windows --release || goto :fail
popd
if exist "%ROOT%dist\studio-windows" rmdir /s /q "%ROOT%dist\studio-windows"
mkdir "%ROOT%dist\studio-windows"
xcopy "%ROOT%apps\studio\build\windows\x64\runner\Release\*" "%ROOT%dist\studio-windows\" /e /i /q /y >nul || goto :fail
echo.
echo Build OK: %ROOT%dist\studio-windows\xcross_studio.exe
pause
exit /b 0
:fail
echo.
echo Build FAILED.
pause
exit /b 1
