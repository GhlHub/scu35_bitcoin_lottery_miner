/******************************************************************************
* Copyright (C) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
* SPDX-License-Identifier: MIT
******************************************************************************/

#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"

#include "xil_printf.h"
#include "xintc.h"
#include "xinterrupt_wrap.h"
#include "xparameters.h"
#include "xtmrctr.h"
#include "xtmrctr_l.h"

static XTmrCtr xTickTimer;
void application_task_return(void) { vAssertCalled("task returned", 0); }

extern void vPortTickISR( void *pvUnused );

void vApplicationSetupTimerInterrupt( void )
{
    const uint32_t ulCyclesPerTick = ( uint32_t ) ( configCPU_CLOCK_HZ / configTICK_RATE_HZ );
    int iStatus;

    configASSERT( ulCyclesPerTick > 0U );

    iStatus = XTmrCtr_Initialize( &xTickTimer, XPAR_XTMRCTR_0_BASEADDR );
    configASSERT( iStatus == XST_SUCCESS );

    XTmrCtr_SetResetValue( &xTickTimer, 0U, ulCyclesPerTick - 1U );
    XTmrCtr_SetOptions( &xTickTimer,
                        0U,
                        XTC_INT_MODE_OPTION |
                        XTC_AUTO_RELOAD_OPTION |
                        XTC_DOWN_COUNT_OPTION );

    iStatus = xPortInstallInterruptHandler( XPAR_XTMRCTR_0_INTERRUPTS,
                                            ( XInterruptHandler ) vPortTickISR,
                                            NULL );
    configASSERT( iStatus == pdPASS );

    /* The SDT MicroBlaze port configures/connects INTC but does not start it.
     * Without real-mode MER enable the timer counts but no RTOS ticks arrive. */
    iStatus = XStartInterruptCntrl( XIN_REAL_MODE,
                                   XPAR_XINTC_0_BASEADDR | XINTC_TYPE_IS_INTC );
    configASSERT( iStatus == XST_SUCCESS );

    vPortEnableInterrupt( XPAR_XTMRCTR_0_INTERRUPTS );
    XTmrCtr_Start( &xTickTimer, 0U );
}

void vApplicationClearTimerInterrupt( void )
{
    const UINTPTR ulBaseAddress = xTickTimer.BaseAddress;
    const u32 ulTcsr = XTmrCtr_ReadReg( ulBaseAddress, 0U, XTC_TCSR_OFFSET );

    XTmrCtr_WriteReg( ulBaseAddress,
                      0U,
                      XTC_TCSR_OFFSET,
                      ulTcsr | XTC_CSR_INT_OCCURED_MASK );
}

void vApplicationMallocFailedHook( void )
{
    xil_printf( "FreeRTOS malloc failed\r\n" );
    taskDISABLE_INTERRUPTS();

    for( ; ; )
    {
    }
}

void vApplicationStackOverflowHook( TaskHandle_t xTask, char *pcTaskName )
{
    ( void ) xTask;

    xil_printf( "FreeRTOS stack overflow in task %s\r\n",
                ( pcTaskName != NULL ) ? pcTaskName : "<unknown>" );

    taskDISABLE_INTERRUPTS();

    for( ; ; )
    {
    }
}

void vAssertCalled( const char *pcFileName, uint32_t ulLine )
{
    xil_printf( "FreeRTOS assert: %s:%lu\r\n",
                pcFileName,
                ( unsigned long ) ulLine );

    taskDISABLE_INTERRUPTS();

    for( ; ; )
    {
    }
}
