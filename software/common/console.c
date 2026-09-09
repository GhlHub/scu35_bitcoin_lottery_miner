/* SPDX-License-Identifier: Apache-2.0 */
#include <stdint.h>
#include "xil_io.h"
#define UART_BASE 0x44A10000U
void console_init(void)
{
    Xil_Out32(UART_BASE + 0x18, 0);
    Xil_Out32(UART_BASE + 0x14, 0);
    Xil_Out32(UART_BASE + 0x20, 50000000U / 115200U - 1U);
    Xil_Out32(UART_BASE + 0x24, 50000000U / (115200U * 5U) - 1U);
    Xil_Out32(UART_BASE + 0x18, 3);
}
void outbyte(char value)
{
    uint32_t guard = 1000000;
    while (Xil_In32(UART_BASE + 0x38) >= 1024 && --guard) {}
    if (guard) Xil_Out32(UART_BASE, (uint8_t)value);
}
char inbyte(void)
{
    while (!Xil_In32(UART_BASE + 0x3c)) {}
    return (char)Xil_In32(UART_BASE + 8);
}
