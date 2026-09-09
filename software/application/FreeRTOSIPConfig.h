/* SPDX-License-Identifier: Apache-2.0 */
#ifndef FREERTOS_IP_CONFIG_H
#define FREERTOS_IP_CONFIG_H
#define ipconfigUSE_IPv4 1
#define ipconfigUSE_IPv6 0
#define ipconfigIPv4_BACKWARD_COMPATIBLE 1
#define ipconfigUSE_DHCP 1
#define ipconfigUSE_DHCP_HOOK 0
#define ipconfigUSE_DNS 1
#define ipconfigUSE_DNS_CACHE 1
#define ipconfigUSE_TCP 1
#define ipconfigUSE_NETWORK_EVENT_HOOK 1
#define ipconfigNETWORK_MTU 1500
#define ipconfigNUM_NETWORK_BUFFER_DESCRIPTORS 24
#define ipconfigIP_TASK_PRIORITY 6
#define ipconfigIP_TASK_STACK_SIZE_WORDS 1536
#define ipconfigEVENT_QUEUE_LENGTH 32
#define ipconfigTCP_RX_BUFFER_LENGTH (8*1460)
#define ipconfigTCP_TX_BUFFER_LENGTH (4*1460)
#define ipconfigUSE_TCP_WIN 1
#define ipconfigTCP_WIN_SEG_COUNT 64
#define ipconfigTCP_RX_WIN_SEG_COUNT 4
#define ipconfigTCP_TX_WIN_SEG_COUNT 2
#define ipconfigDRIVER_INCLUDED_TX_IP_CHECKSUM 0
#define ipconfigDRIVER_INCLUDED_RX_IP_CHECKSUM 0
#define ipconfigZERO_COPY_TX_DRIVER 0
#define ipconfigZERO_COPY_RX_DRIVER 0
#define ipconfigBYTE_ORDER pdFREERTOS_LITTLE_ENDIAN
#define ipconfigHAS_DEBUG_PRINTF 0
#define ipconfigHAS_PRINTF 0
#define ipconfigUSE_LLMNR 0
#define ipconfigUSE_NBNS 0
#define ipconfigUSE_MDNS 0
#define ipconfigSUPPORT_SELECT_FUNCTION 1
#define ipconfigSOCK_DEFAULT_RECEIVE_BLOCK_TIME pdMS_TO_TICKS(100)
#define ipconfigSOCK_DEFAULT_SEND_BLOCK_TIME pdMS_TO_TICKS(1000)
#endif
