#ifndef UART_H_
#define UART_H_

#include <stdint.h>
#include <string.h>

// Проверить, начинается ли строка с заданного префикса
// Возвращает 1, если да, иначе 0
#define CMD_IS(cmd, prefix) \
(strncmp((const char*)(cmd), (prefix), sizeof(prefix)-1) == 0)

// Получить указатель на часть строки ПОСЛЕ префикса
// Например, после "set_rpm" будет указатель на число
#define CMD_ARG(cmd, prefix) \
((char*)(cmd) + sizeof(prefix)-1)

// ====================================================================
//  РАЗМЕРЫ БУФЕРОВ
// ====================================================================

#define RX_BUFFER_SIZE   16    // Приёмный буфер
#define TX_BUFFER_SIZE   64    // Передающий буфер

// ====================================================================
//  ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ (extern)
// ====================================================================

extern volatile char rx_buffer[RX_BUFFER_SIZE];
extern volatile uint8_t rx_index;
extern volatile uint8_t rx_complete;

// ====================================================================
//  ПРОТОТИПЫ
// ====================================================================

void usart_init(void);
void usart_transmit_byte(uint8_t data);      // Добавить байт в буфер передачи
void usart_transmit_string(const char str[]); // Добавить строку в буфер передачи
void usart_flush_tx(void);                    // Дождаться окончания передачи (если нужно)

uint8_t usart_receive_byte(void);             // Блокирующий приём байта (оставлен для совместимости)
void clear_rx_buffer(void);                   // Очистить приёмный буфер

#endif

// -------КАК ИСПОЛЬЗОВАТЬ ПРИЁМ КОМАНД В MAIN:----------
// if (CMD_IS(rx_buffer, "set_rpm"))
//{
//	setpoint_rpm = atoi(CMD_ARG(rx_buffer, "set_rpm"));
//}