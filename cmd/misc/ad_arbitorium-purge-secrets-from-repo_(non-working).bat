
setlocal enabledelayedexpansion

REM Base directory to scan
set "searchDir=%~dp0"

REM Exact filenames
set exactList=system.yaml ceph.conf

REM Suffix patterns
set suffixList=.smbcreds .env

echo Scanning for matching files in: %searchDir%
echo.

REM Walk every file recursively
for /r "%searchDir%" %%f in (*) do (
    set "fname=%%~nxf"
    set "matched="

    REM === Check exact matches ===
    for %%e in (%exactList%) do (
        if /i "!fname!"=="%%e" (
            set "matched=1"
        )
    )

    REM === Check suffix matches ===
    for %%s in (%suffixList%) do (
        set "suffix=%%s"
        set "len=0"
        call :strlen suffix len
        set "tail=!fname:~-!len!!"
        if /i "!tail!"=="%%s" (
            set "matched=1"
        )
    )

    if defined matched (
        echo Deleting: "%%f"
        del "%%f"
        if errorlevel 1 echo Failed to delete: %%f
    )
)

echo.
echo Done.
pause
endlocal
goto :eof

REM === Get length of a string ===
:strlen
setlocal enabledelayedexpansion
set "str=!%1!"
set "len=0"
:loop
if defined str (
    set "str=!str:~1!"
    set /a len+=1
    goto :loop
)
endlocal & set "%2=%len%"
exit /b