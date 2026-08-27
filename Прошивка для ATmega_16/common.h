/*
 * common.h
 *
 * Created: 24.08.2026 14:42:19
 *  Author: marsel
 */ 


#ifndef COMMON_H_
#define COMMON_H_


#define  F_CPU 16000000UL
#include <avr/io.h>
#include <avr/interrupt.h>
#include <string.h>     // Для strcmp, strncmp
#include <stdlib.h>     // Для atoi
#include "UART.h"       // Наша UART-библиотека с неблокирующим приёмом ДОРАБОТАННАЯ БИБЛИОТЕКА
#include <avr/eeprom.h>
#include <stdint.h>     // uint16_t и тд


#endif /* COMMON_H_ */