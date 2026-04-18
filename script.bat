@echo off
setlocal enabledelayedexpansion

:: Define paths
set SRC_DIR=.\src
set TEST_DIR=.\tests
set TEST_DIR_FP=.\tests_fp
set SIM_DIR=.\sim
set SRC_DIR_FP=.\src_fp
set SRC_DIR_SYSTOLIC=.\src_systolic_array
set SRC_DIR_MULT=.\src_mult_csr_dma_fp
set TEST_DIR_SYSTOLIC=.\tests_systolic_array
set TEST_DIR_MULT=.\tests_mult_csr

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

echo ------------------------------------------------
echo    Floating Point Unit (FPU) Tests
echo ------------------------------------------------
echo 7) Test FP MAC Unit
echo 8) Test Full FPU
echo ------------------------------------------------
echo 9) Test rv32i Base Instructions with FP
echo 10) Torture Test for rv32i with FP
echo ------------------------------------------------
echo 11) Test FP SoC (Top Level with FP)

echo ------------------------------------------------
echo    Systolic Array and DMA Tests
echo ------------------------------------------------
echo 12) Test MAC for Systolic Array
echo 13) Test Systolic Array
echo ------------------------------------------------
echo 14) Test rv32i for DMA in Systolic Array
echo 15) Test rv32i Base Instructions for DMA in Systolic Array
echo ------------------------------------------------
echo 16) Test FP Instructions for DMA in Systolic Array
echo ------------------------------------------------
echo 17) Test FP DMA Systolic Array SoC

echo ------------------------------------------------
echo 18) Test rv32i Base Instructions with Multiply and CSR (New)
echo 19) Test FP Instructions with Multiply and CSR (New)
echo 20) Test dma instructions with Multiply and CSR (New)
echo ------------------------------------------------
echo 21) Test Multiply Instructions (New)
echo 22) Test all except interrupt 
echo 23) Test Interrupt Handling (New)
echo 24) Test All Modules (Comprehensive Testbench)

echo q) Quit
echo ------------------------------------------------
set /p choice="Choose a module to verify: "

if "%choice%"=="1" (
    set MODULE=alu
    set TB_FILE=%TEST_DIR%\alu_tb.sv
    set SOURCE_DIR=%SRC_DIR%
) else if "%choice%"=="2" (
    set MODULE=regfile
    set TB_FILE=%TEST_DIR%\regfile_tb.sv
    set SOURCE_DIR=%SRC_DIR%
) else if "%choice%"=="3" (
    set MODULE=controller
    set TB_FILE=%TEST_DIR%\controller_tb.sv
    set SOURCE_DIR=%SRC_DIR%

) else if "%choice%"=="4" (
    set MODULE=hazard_unit
    set TB_FILE=%TEST_DIR%\hazard_unit_tb.sv
    set SOURCE_DIR=%SRC_DIR%
) else if "%choice%"=="5" (
    set MODULE=soc
    set TB_FILE=%TEST_DIR%\soc_tb.sv
    set SOURCE_DIR=%SRC_DIR%
) else if "%choice%"=="6" (
    set MODULE=torture_test
    set TB_FILE=%TEST_DIR%\rv32i_base_torture_tb.sv
    set SOURCE_DIR=%SRC_DIR%
) else if "%choice%"=="7" (
    set MODULE=fp_mac
    set TB_FILE=%TEST_DIR_FP%\fp_mac_tb.sv
    set SOURCE_DIR=%SRC_DIR_FP%
) else if "%choice%"=="8" (
    set MODULE=fpu
    set TB_FILE=%TEST_DIR_FP%\fpu_tb.sv
    set SOURCE_DIR=%SRC_DIR_FP%
) else if "%choice%"=="9" (
    set MODULE=riscv_fp
    set TB_FILE=%TEST_DIR_FP%\rv32i_base_instr.sv
    set SOURCE_DIR=%SRC_DIR_FP%
) else if "%choice%"=="10" (
    set MODULE=riscv_fp_torture
    set TB_FILE=%TEST_DIR_FP%\rv32i_base_torture_tb.sv
    set SOURCE_DIR=%SRC_DIR_FP%
) else if "%choice%"=="11" (
    set MODULE=riscv_fp_tsoc
    set TB_FILE=%TEST_DIR_FP%\fp_soc_tb.sv
    set SOURCE_DIR=%SRC_DIR_FP%
) else if "%choice%"=="12" (
    set MODULE=mac_for_SA
    set TB_FILE=%TEST_DIR_SYSTOLIC%\MAC_tb.v
    set SOURCE_DIR=%SRC_DIR_SYSTOLIC%
) else if "%choice%"=="13" (
    set MODULE=systolic_array
    set TB_FILE=%TEST_DIR_SYSTOLIC%\matmul_tb.v
    set SOURCE_DIR=%SRC_DIR_SYSTOLIC%
) else if "%choice%"=="14" (
    set MODULE=riscv_fp_torture_dma
    set TB_FILE=%TEST_DIR_SYSTOLIC%\rv32i_base_torture_tb_dma.sv
    set SOURCE_DIR=%SRC_DIR_SYSTOLIC%
) else if "%choice%"=="15" (
    set MODULE=riscv_base_instr_dma
    set TB_FILE=%TEST_DIR_SYSTOLIC%\rv32i_base_instr.sv
    set SOURCE_DIR=%SRC_DIR_SYSTOLIC%
) else if "%choice%"=="16" (
    set MODULE=fp_instr_dma
    set TB_FILE=%TEST_DIR_SYSTOLIC%\fp_instr_tb.sv
    set SOURCE_DIR=%SRC_DIR_SYSTOLIC%
) else if "%choice%"=="17" (
    set MODULE=fp_dma_systolic_array_test
    set TB_FILE=%TEST_DIR_SYSTOLIC%\dma_fp_soc_tb.v
    set SOURCE_DIR=%SRC_DIR_SYSTOLIC%
) else if "%choice%"=="18" (
    set MODULE=mul_csr_riscv_instr
    set TB_FILE=%TEST_DIR_MULT%\rv32i_base_torture_tb.sv
    set SOURCE_DIR=%SRC_DIR_MULT%
) else if "%choice%"=="19" (
    set MODULE=mul_csr_pe_fp_instr
    set TB_FILE=%TEST_DIR_MULT%\fp_instr_tb.sv
    set SOURCE_DIR=%SRC_DIR_MULT%
) else if "%choice%"=="20" (
    set MODULE=mul_csr_pe_dma_gpio_instr
    set TB_FILE=%TEST_DIR_MULT%\dma_fp_soc_tb.v
    set SOURCE_DIR=%SRC_DIR_MULT%
) else if "%choice%"=="21" (
    set MODULE=mult_instr
    set TB_FILE=%TEST_DIR_MULT%\mult_instr_tb.v
    set SOURCE_DIR=%SRC_DIR_MULT%

) else if "%choice%"=="22" (
    set MODULE=all
    set TB_FILE=%TEST_DIR_MULT%\mul_dma_gpio_checkpt_tb.v
    set SOURCE_DIR=%SRC_DIR_MULT%

) else if "%choice%"=="23" (
    set MODULE=interrupt_test
    set TB_FILE=%TEST_DIR_MULT%\interrupt_tb.v
    set SOURCE_DIR=%SRC_DIR_MULT%

) else if "%choice%"=="24" (
    set MODULE=comprehensive_test
    set TB_FILE=%TEST_DIR_MULT%\all_tb.v
    set SOURCE_DIR=%SRC_DIR_MULT%

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

iverilog -g2012 -I %SOURCE_DIR%  -o %SIM_DIR%\!MODULE!_sim.out !TB_FILE!

if %ERRORLEVEL% equ 0 (
    echo Running Simulation...
    vvp %SIM_DIR%\!MODULE!_sim.out
) else (
    echo Compilation Failed!
)

pause
goto menu