// ============================================================================
//  ПОДКЛЮЧАЕМ ОБЩИЙ ЗАГОЛОВОК (содержит все нужные библиотеки и макросы)
// ============================================================================
#include "common.h"

void uart_processing(void); // прототип обработки rx
// ============================================================================
//  НАСТРОЙКИ (ранее были #define, теперь стали переменными)
// ============================================================================
// Параметры вентилятора, изменяемые с ПК
int temp_off = 35;         // Ниже этой температуры вентилятор выключается
int temp_on = 40;          // Выше этой температуры вентилятор включается
int temp_max = 60;         // Максимальная рабочая температура
int fan_max_rpm = 2200;    // Максимальные обороты
int fan_min_rpm = 880;     // Минимальные обороты (40% от максимума)

#define PULSES_PER_REVOLUTION   2   // Импульсов на один оборот вентилятора (обычно 2)
#define TIMER_TICKS_PER_SEC     61  // Переполнений Timer0 для 1 секунды (16,384 мс * 61 ? 1 с)

#define KP  2.0f                 // Пропорциональный коэффициент ПИ-регулятора
#define KI  0.5f                 // Интегральный коэффициент ПИ-регулятора

#define PWM_TOP  639             // TOP для ШИМ (25 кГц при 16 МГц, предделитель 1)
#define PWM_MIN  0               // Минимальный ШИМ (вентилятор остановлен)
#define PWM_MAX  639             // Максимальный ШИМ (100%)

// ============================================================================
//  ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
// ============================================================================

volatile char fan_active = 0;               // Состояние вентилятора: 0 — выкл, 1 — вкл
volatile unsigned int pulse_count = 0;      // Счётчик импульсов тахометра
volatile unsigned int current_rpm = 0;      // Текущие обороты (обновляется раз в секунду)
volatile unsigned char rpm_update = 0;      // Флаг: пора обновить RPM и выполнить регулирование

volatile char automode = 0;                 // 0 — ручной (set_rpm), 1 — автоматический по температуре
volatile int setpoint_rpm = 0;              // Уставка (желаемые обороты)

int temp = 20;                              // Текущая температура. ЗАМЕЧАНИЕ: заглушка!
// В реальном проекте обновляйте её из датчика
// (например, DS18B20) или по UART.

int integral = 0;                           // Интегральная составляющая ПИ-регулятора
char buf[10];                               // Буфер для itoa

// ============================================================================
//  ПРЕРЫВАНИЕ ТАХОМЕТРА (INT0) — считается импульс от вентилятора
// ============================================================================

ISR(INT0_vect)
{
	pulse_count++;   // Каждый передний фронт от тахометрического выхода
}

// ============================================================================
//  ПРЕРЫВАНИЕ ТАЙМЕРА 0 — обновление RPM раз в секунду
// ============================================================================

ISR(TIMER0_OVF_vect)
{
	static unsigned int timer_count = 0;

	timer_count++;
	if (timer_count >= TIMER_TICKS_PER_SEC)
	{
		timer_count = 0;

		// Пересчёт импульсов в RPM: (имп/сек) * 60 / (имп/оборот)
		current_rpm = (pulse_count * 60) / PULSES_PER_REVOLUTION;
		pulse_count = 0;

		rpm_update = 1;   // Сообщаем main: пора регулировать
	}
}

// ============================================================================
//  ИНИЦИАЛИЗАЦИЯ ШИМ (Timer1, Fast PWM, 25 кГц, PD5)
// ============================================================================

void pwm_init(void)
{
	DDRD |= (1 << 5);   // PD5 (OC1A) — выход

	TCCR1A = (1 << COM1A1) | (1 << WGM11);
	TCCR1B = (1 << WGM13) | (1 << WGM12) | (1 << CS10);   // Предделитель 1

	ICR1 = PWM_TOP;     // 639 -> 25 кГц
	OCR1A = 0;          // Начальный ШИМ 0%
}

// ============================================================================
//  ИНИЦИАЛИЗАЦИЯ ТАХОМЕТРА (INT0) И ТАЙМЕРА 0
// ============================================================================

void tachometer_init(void)
{
	DDRD &= ~(1 << 2);   // PD2 — вход
	PORTD |= (1 << 2);   // Внутренняя подтяжка

	MCUCR |= (1 << ISC01) | (1 << ISC00);   // Внешнее прерывание по переднему фронту
	GICR  |= (1 << INT0);                    // Разрешаем INT0

	TCCR0 = (1 << CS02) | (1 << CS00);       // Таймер 0: делитель 1024
	TCNT0 = 0;
	TIMSK |= (1 << TOIE0);                   // Прерывание по переполнению
}

// ============================================================================
//  ПИ-РЕГУЛЯТОР
// ============================================================================

void pi_control(void)
{
	int error = setpoint_rpm - (int)current_rpm;

	integral += error;

	// Анти-виндап: ограничиваем интеграл
	if (integral > 1000) integral = 1000;
	if (integral < -1000) integral = -1000;

	int output = (int)(KP * error + KI * integral);

	// Ограничение ШИМ
	if (output > PWM_MAX) output = PWM_MAX;
	if (output < PWM_MIN) output = PWM_MIN;

	OCR1A = output;
}

// ============================================================================
//  АВТОМАТИЧЕСКАЯ УСТАВКА ОБОРОТОВ ПО ТЕМПЕРАТУРЕ (с гистерезисом)
// ============================================================================

int update_fan_setpoint(int temp)
{
	// Гистерезис включения/выключения
	if (fan_active == 0 && temp >= temp_on)
	fan_active = 1;                      // Включаем при temp_on
	else if (fan_active == 1 && temp <= temp_off)
	fan_active = 0;                      // Выключаем при temp_off

	if (fan_active == 0)
	return 0;                            // Вентилятор выключен

	// Включён: считаем RPM в зависимости от температуры
	if (temp <= temp_on)
	return fan_min_rpm;                  // Стартуем с минимальных оборотов

	if (temp >= temp_max)
	return fan_max_rpm;                  // Максимальные обороты

	// Линейный рост от fan_min_rpm (при temp_on) до fan_max_rpm (при temp_max)
	return fan_min_rpm + (temp - temp_on) * (fan_max_rpm - fan_min_rpm) / (temp_max - temp_on);
}

// ============================================================================
//  MAIN
// ============================================================================

int main(void)
{
	DDRB |= (1 << 0);          // PB0 как выход (например, светодиод индикации)

	pwm_init();
	tachometer_init();
	usart_init();
	sei();

	// Чтение сохранённых параметров из EEPROM
	// Адреса: 0 - setpoint_rpm (уже используем), 2 - temp_off, 4 - temp_on, 6 - temp_max, 8 - fan_min_rpm, 10 - fan_max_rpm
	setpoint_rpm = eeprom_read_word((uint16_t*)0);
	temp_off = eeprom_read_word((uint16_t*)2);
	temp_on = eeprom_read_word((uint16_t*)4);
	temp_max = eeprom_read_word((uint16_t*)6);
	fan_min_rpm = eeprom_read_word((uint16_t*)8);
	fan_max_rpm = eeprom_read_word((uint16_t*)10);

	// ЗАМЕЧАНИЕ ИСПРАВЛЕНО: проверка на мусор при первом включении
	if (setpoint_rpm > fan_max_rpm || setpoint_rpm < 0)
	setpoint_rpm = 0;   // Или fan_min_rpm, если хотите, чтобы вентилятор стартовал с минимальных
	if (temp_off > temp_on || temp_off < 0) temp_off = 35;
	if (temp_on >= temp_max || temp_on < 0) temp_on = 40;
	if (temp_max <= temp_on || temp_max > 150) temp_max = 60;
	if (fan_min_rpm > fan_max_rpm || fan_min_rpm < 0) fan_min_rpm = 880;
	if (fan_max_rpm < fan_min_rpm || fan_max_rpm > 5000) fan_max_rpm = 2200;

	usart_transmit_string("Fan controller ready\r\n");

	while(1)
	{
		uart_processing(); // обработка команд rx_data
		
		// ----- РЕГУЛИРОВАНИЕ РАЗ В СЕКУНДУ -----
		if (rpm_update) // получили данные с таходатчика
		{
			rpm_update = 0;

			// ЗАМЕЧАНИЕ ИСПРАВЛЕНО: обновляем уставку ДО pi_control()
			if (automode)
			setpoint_rpm = update_fan_setpoint(temp);

			// Индикация: если уставка больше 2000 — включить PB0 (для отладки)
			if (setpoint_rpm > 2000)
			PORTB |= (1 << 0);
			else
			PORTB &= ~(1 << 0);

			// Вывод отладочной информации
			usart_transmit_string("RPM: ");
			itoa(current_rpm, buf, 10);
			usart_transmit_string(buf);

			usart_transmit_string("  Set: ");
			itoa(setpoint_rpm, buf, 10);
			usart_transmit_string(buf);

			usart_transmit_string("  PWM: ");
			itoa(OCR1A, buf, 10);
			usart_transmit_string(buf);

			usart_transmit_string("\r\n");

			// Выполняем шаг ПИ-регулятора
			pi_control();
		}

		// ЗАМЕЧАНИЕ: здесь можно добавить чтение температуры из датчика
		// Например: temp = ds18b20_task();
	}
}
// ----- ОБРАБОТКА КОМАНД ИЗ UART -----	
	void uart_processing(void)
{                              
	  if (rx_complete)
	  {
		rx_complete = 0;

		if (CMD_IS(rx_buffer, "set_rpm") && !automode)
		{
			// Ручная установка оборотов
			setpoint_rpm = atoi(CMD_ARG(rx_buffer, "set_rpm"));

			// Ограничение
			if (setpoint_rpm < 0) setpoint_rpm = 0;
			if (setpoint_rpm > fan_max_rpm) setpoint_rpm = fan_max_rpm;

			// Сохраняем в EEPROM
			eeprom_write_word((uint16_t*)0, setpoint_rpm);

			usart_transmit_string("Set RPM: ");
			itoa(setpoint_rpm, buf, 10);
			usart_transmit_string(buf);
			usart_transmit_string("\r\n");
		}
		else if (CMD_IS(rx_buffer, "auto"))
		{
			automode = 1;
			integral = 0;   // ЗАМЕЧАНИЕ ИСПРАВЛЕНО: сброс интеграла при смене режима
			usart_transmit_string("Set: AUTO \r\n");
		}
		else if (CMD_IS(rx_buffer, "manual"))
		{
			automode = 0;
			integral = 0;
			usart_transmit_string("Set: MANUAL \r\n");
		}
		else if (CMD_IS(rx_buffer, "set_temp_off"))
		{
			temp_off = atoi(CMD_ARG(rx_buffer, "set_temp_off"));
			if (temp_off > temp_on || temp_off < 0) temp_off = 35;
			eeprom_write_word((uint16_t*)2, temp_off);
			usart_transmit_string("Temp off: ");
			itoa(temp_off, buf, 10);
			usart_transmit_string(buf);
			usart_transmit_string("\r\n");
		}
		else if (CMD_IS(rx_buffer, "set_temp_on"))
		{
			temp_on = atoi(CMD_ARG(rx_buffer, "set_temp_on"));
			if (temp_on >= temp_max || temp_on <= temp_off) temp_on = 40;
			eeprom_write_word((uint16_t*)4, temp_on);
			usart_transmit_string("Temp on: ");
			itoa(temp_on, buf, 10);
			usart_transmit_string(buf);
			usart_transmit_string("\r\n");
		}
		else if (CMD_IS(rx_buffer, "set_temp_max"))
		{
			temp_max = atoi(CMD_ARG(rx_buffer, "set_temp_max"));
			if (temp_max <= temp_on || temp_max > 150) temp_max = 60;
			eeprom_write_word((uint16_t*)6, temp_max);
			usart_transmit_string("Temp max: ");
			itoa(temp_max, buf, 10);
			usart_transmit_string(buf);
			usart_transmit_string("\r\n");
		}
		else if (CMD_IS(rx_buffer, "set_fan_min"))
		{
			fan_min_rpm = atoi(CMD_ARG(rx_buffer, "set_fan_min"));
			if (fan_min_rpm > fan_max_rpm || fan_min_rpm < 0) fan_min_rpm = 880;
			eeprom_write_word((uint16_t*)8, fan_min_rpm);
			usart_transmit_string("Fan min: ");
			itoa(fan_min_rpm, buf, 10);
			usart_transmit_string(buf);
			usart_transmit_string("\r\n");
		}
		else if (CMD_IS(rx_buffer, "set_fan_max"))
		{
			fan_max_rpm = atoi(CMD_ARG(rx_buffer, "set_fan_max"));
			if (fan_max_rpm < fan_min_rpm || fan_max_rpm > 5000) fan_max_rpm = 2200;
			eeprom_write_word((uint16_t*)10, fan_max_rpm);
			usart_transmit_string("Fan max: ");
			itoa(fan_max_rpm, buf, 10);
			usart_transmit_string(buf);
			usart_transmit_string("\r\n");
		}
		else if (CMD_IS(rx_buffer, "set_temp")) // Приём температуры с пк
		{
			temp = atoi(CMD_ARG(rx_buffer, "set_temp"));
			// Можно сохранять в EEPROM, но не обязательно
			usart_transmit_string("Temp set: ");
			itoa(temp, buf, 10);
			usart_transmit_string(buf);
			usart_transmit_string("\r\n");
		}

		clear_rx_buffer();
	}
  
}