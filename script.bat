@echo off
setlocal enabledelayedexpansion

:: Define paths
set SRC_DIR=.\src
set TEST_DIR=.\tests
set SIM_DIR=.\sim

:: Create sim directory if it doesn't exist
if not exist %SIM_DIR% mkdir %SIM_DIR%

:menu
cls
echo ------------------------------------------------
echo    IITB RISC-V Modular Verification (Windows)
echo ------------------------------------------------
echo 1) Test ALU
echo 2) Test Register File
echo 3) Test Controller
echo 4) Test Hazard Unit
echo 5) Test Full SoC (Top Level)
echo 6) Torture Test for rv32i
echo q) Quit
echo ------------------------------------------------
set /p choice="Choose a module to verify: "

if "%choice%"=="1" (
    set MODULE=alu
    set TB_FILE=%TEST_DIR%\alu_tb.sv
) else if "%choice%"=="2" (
    set MODULE=regfile
    set TB_FILE=%TEST_DIR%\regfile_tb.sv
) else if "%choice%"=="3" (
    set MODULE=controller
    set TB_FILE=%TEST_DIR%\controller_tb.sv
) else if "%choice%"=="4" (
    set MODULE=hazard_unit
    set TB_FILE=%TEST_DIR%\hazard_unit_tb.sv
) else if "%choice%"=="5" (
    set MODULE=soc
    set TB_FILE=%TEST_DIR%\soc_tb.sv
) else if "%choice%"=="6" (
    set MODULE=torture_test
    set TB_FILE=%TEST_DIR%\rv32i_base_torture_tb.sv
) else if "%choice%"=="q" (
    exit /b
) else (
    echo Invalid choice.
    pause
    goto menu
)

echo Compiling !MODULE!...
:: -g2012 enables SystemVerilog assertions
:: -I points to your src folder
iverilog -g2012 -I %SRC_DIR% -o %SIM_DIR%\!MODULE!_sim.out !TB_FILE!

if %ERRORLEVEL% equ 0 (
    echo Running Simulation...
    vvp %SIM_DIR%\!MODULE!_sim.out
) else (
    echo Compilation Failed!
)

pause
goto menu