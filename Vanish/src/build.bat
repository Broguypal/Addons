@echo off
REM Build _Vanish.dll with MSVC. Run from a "x86 Native Tools Command Prompt".
REM 32-bit is mandatory: FFXI and Windower are both x86.

setlocal
set OUT=..\libs\_Vanish.dll
if not exist ..\libs mkdir ..\libs

cl /nologo /LD /O2 /EHsc /std:c++17 /W4 /DNDEBUG ^
   VanishModule.cpp ^
   /link /MACHINE:X86 /OUT:%OUT% kernel32.lib

if errorlevel 1 (
    echo BUILD FAILED
    exit /b 1
)

del /q *.obj *.exp *.lib 2>nul
echo Built %OUT%
endlocal
