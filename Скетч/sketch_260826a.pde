import processing.javafx.*;
import java.io.BufferedReader;
import java.io.InputStreamReader;
import processing.serial.*;

Serial myPort;
boolean connected = false;
String portName = "";

// --- Глобальные переменные интерфейса ---
int currentRPM = 0, currentSet = 0, currentPWM = 0;
int cpuTemp = 0;
boolean cpuTempValid = false;

boolean autoMode = false;

// Ползунок RPM
int sliderX = 400, sliderY = 250, sliderW = 200;
int sliderMin = 0, sliderMax = 2200;
int rpmValue = 0;
boolean sliderDragging = false;

// Текстовые поля
int fieldX = 400, fieldW = 80, fieldH = 25;
int fieldY_tempOff = 300;
int fieldY_tempOn  = 340;
int fieldY_tempMax = 380;
int fieldY_fanMin = 420;
int fieldY_fanMax = 460;

String tempOffText = "35";
String tempOnText  = "40";
String tempMaxText = "60";
String fanMinText  = "880";
String fanMaxText  = "2200";

int activeField = -1; // -1 = нет активного поля

// --- Панель выбора порта ---
String[] portList = {};
int selectedPortIndex = 0;
String[] baudRates = {"9600", "19200", "38400", "57600", "115200"};
int selectedBaudIndex = 0;

boolean portDropdownOpen = false;
boolean baudDropdownOpen = false;

int connectBtnX = 550, connectBtnY = 20, connectBtnW = 120, connectBtnH = 40;

// Для отображения последнего действия
String lastAction = "";

// Таймер отправки температуры
int lastTempSendTime = 0;
int tempSendInterval = 5000; // мс

void setup() {
  size(700, 550, FX2D);
  textFont(createFont("Tahoma", 16));
  smooth(8);

  refreshPortList();

  if (portList.length > 0) {
    selectedPortIndex = portList.length - 1;
    connectToPort();
  }

  // Поток для обновления температуры CPU
  thread("updateCpuTemp");
}

void refreshPortList() {
  try {
    portList = Serial.list();
  } catch (Exception e) {
    println("Error listing ports: " + e.getMessage());
    portList = new String[0];
  }
}

void connectToPort() {
  if (portList.length == 0) {
    connected = false;
    lastAction = "No ports available";
    return;
  }
  String port = portList[selectedPortIndex];
  int baud = int(baudRates[selectedBaudIndex]);
  try {
    if (myPort != null) {
      myPort.stop();
      myPort = null;
    }
    myPort = new Serial(this, port, baud);
    myPort.bufferUntil('\n');
    connected = true;
    portName = port;
    lastAction = "Connected to " + port + " at " + baud;
  } catch (Exception e) {
    connected = false;
    myPort = null;
    lastAction = "Connection failed: " + e.getMessage();
  }
}

void disconnectPort() {
  if (myPort != null) {
    myPort.stop();
    myPort = null;
  }
  connected = false;
  lastAction = "Disconnected";
}

void draw() {
  background(240);

  // --- Верхняя панель выбора порта ---
  fill(0);
  textSize(14);
  text("Port:", 30, 35);
  drawDropdown(70, 20, 150, 30, portList.length > 0 ? portList[selectedPortIndex] : "No ports", portDropdownOpen);
  text("Baud:", 240, 35);
  drawDropdown(290, 20, 100, 30, baudRates[selectedBaudIndex], baudDropdownOpen);

  // Кнопка Connect/Disconnect
  if (connected) {
    fill(200, 100, 100);
    stroke(0);
    rect(connectBtnX, connectBtnY, connectBtnW, connectBtnH, 5);
    fill(0);
    textAlign(CENTER, CENTER);
    text("Disconnect", connectBtnX + connectBtnW/2, connectBtnY + connectBtnH/2);
    textAlign(LEFT, BASELINE);
  } else {
    fill(100, 200, 100);
    stroke(0);
    rect(connectBtnX, connectBtnY, connectBtnW, connectBtnH, 5);
    fill(0);
    textAlign(CENTER, CENTER);
    text("Connect", connectBtnX + connectBtnW/2, connectBtnY + connectBtnH/2);
    textAlign(LEFT, BASELINE);
  }

  // --- Основной интерфейс ---
  fill(0);
  textSize(20);
  text("Fan Controller", 50, 100);

  textSize(14);
  fill(0);
  text("Current values:", 50, 130);
  text("RPM: " + currentRPM, 50, 150);
  text("Set: " + currentSet, 50, 170);
  text("PWM: " + currentPWM, 50, 190);

  // Температура CPU
  if (cpuTempValid) {
    fill(0);
    text("CPU Temp: " + cpuTemp + " C", 50, 210);
  } else {
    fill(150);
    text("CPU Temp: N/A", 50, 210);
  }

  // Кнопки AUTO/MANUAL
  drawButton(200, 120, 100, 30, "AUTO", autoMode ? color(0,200,0) : color(200));
  drawButton(320, 120, 100, 30, "MANUAL", !autoMode ? color(0,200,0) : color(200));

  // Ползунок RPM
  drawSlider(sliderX, sliderY, sliderW, rpmValue, sliderMin, sliderMax, autoMode);

  // Текстовые поля
  drawTextField(fieldX, fieldY_tempOff, fieldW, fieldH, "Temp Off", tempOffText, activeField == 0);
  drawTextField(fieldX, fieldY_tempOn,  fieldW, fieldH, "Temp On",  tempOnText,  activeField == 1);
  drawTextField(fieldX, fieldY_tempMax, fieldW, fieldH, "Temp Max", tempMaxText, activeField == 2);
  drawTextField(fieldX, fieldY_fanMin, fieldW, fieldH, "Fan Min", fanMinText, activeField == 3);
  drawTextField(fieldX, fieldY_fanMax, fieldW, fieldH, "Fan Max", fanMaxText, activeField == 4);

  fill(100);
  text("Click field, type digits, press Enter to send.", 50, 510);
  fill(0);
  text("Last action: " + lastAction, 50, 530);

  // Выпадающие списки
  if (portDropdownOpen) {
    drawDropdownItems(70, 50, 150, portList, selectedPortIndex);
  }
  if (baudDropdownOpen) {
    drawDropdownItems(290, 50, 100, baudRates, selectedBaudIndex);
  }

  // Периодическая отправка температуры на МК
  if (connected && cpuTempValid && millis() - lastTempSendTime > tempSendInterval) {
    sendCommand("set_temp " + cpuTemp);
    lastTempSendTime = millis();
  }
}

// --- Функции отрисовки ---
void drawButton(int x, int y, int w, int h, String label, color col) {
  fill(col);
  stroke(0);
  rect(x, y, w, h, 5);
  fill(0);
  textAlign(CENTER, CENTER);
  text(label, x + w/2, y + h/2);
  textAlign(LEFT, BASELINE);
}

void drawSlider(int x, int y, int w, float value, float minV, float maxV, boolean enabled) {
  stroke(0);
  if (enabled) fill(255);
  else fill(200);
  rect(x-5, y-10, w+10, 20, 3);
  float pos = map(value, minV, maxV, x, x+w);
  if (enabled) fill(100, 100, 255);
  else fill(150);
  ellipse(pos, y, 10, 20);
  fill(0);
  text("RPM: " + int(value), x - 100, y + 5);
}

void drawTextField(int x, int y, int w, int h, String label, String content, boolean active) {
  stroke(0);
  if (active) fill(230, 230, 255);
  else fill(255);
  rect(x, y, w, h, 3);
  fill(0);
  textAlign(LEFT, CENTER);
  text(content, x + 5, y + h/2);
  textAlign(LEFT, BASELINE);
  fill(0);
  text(label + ":", x - 100, y + h/2);
}

void drawDropdown(int x, int y, int w, int h, String label, boolean open) {
  stroke(0);
  if (open) fill(230, 230, 255);
  else fill(255);
  rect(x, y, w, h, 3);
  fill(0);
  textAlign(LEFT, CENTER);
  text(label, x + 5, y + h/2);
  // стрелочка
  fill(0);
  triangle(x+w-15, y+10, x+w-5, y+10, x+w-10, y+20);
  textAlign(LEFT, BASELINE);
}

void drawDropdownItems(int x, int y, int w, String[] items, int selected) {
  for (int i = 0; i < items.length; i++) {
    if (i == selected) fill(200, 200, 255);
    else fill(255);
    stroke(0);
    rect(x, y + i*25, w, 25);
    fill(0);
    text(items[i], x+5, y + i*25 + 17);
  }
}

// --- Обработка мыши ---
void mousePressed() {
  // Клик по дропдауну портов
  if (mouseX > 70 && mouseX < 220 && mouseY > 20 && mouseY < 50) {
    portDropdownOpen = !portDropdownOpen;
    baudDropdownOpen = false;
    return;
  }
  // Клик по дропдауну скоростей
  if (mouseX > 290 && mouseX < 390 && mouseY > 20 && mouseY < 50) {
    baudDropdownOpen = !baudDropdownOpen;
    portDropdownOpen = false;
    return;
  }

  // Клик по пунктам выпадающего списка портов
  if (portDropdownOpen) {
    int itemHeight = 25;
    for (int i = 0; i < portList.length; i++) {
      if (mouseX > 70 && mouseX < 220 && mouseY > 50 + i*itemHeight && mouseY < 50 + (i+1)*itemHeight) {
        selectedPortIndex = i;
        portDropdownOpen = false;
        return;
      }
    }
    portDropdownOpen = false;
  }

  // Клик по пунктам выпадающего списка скоростей
  if (baudDropdownOpen) {
    int itemHeight = 25;
    for (int i = 0; i < baudRates.length; i++) {
      if (mouseX > 290 && mouseX < 390 && mouseY > 50 + i*itemHeight && mouseY < 50 + (i+1)*itemHeight) {
        selectedBaudIndex = i;
        baudDropdownOpen = false;
        return;
      }
    }
    baudDropdownOpen = false;
  }

  // Клик по кнопке Connect/Disconnect
  if (mouseX > connectBtnX && mouseX < connectBtnX + connectBtnW && mouseY > connectBtnY && mouseY < connectBtnY + connectBtnH) {
    if (connected) {
      disconnectPort();
    } else {
      connectToPort();
    }
    return;
  }

  // Кнопки AUTO/MANUAL
  if (mouseX > 200 && mouseX < 300 && mouseY > 120 && mouseY < 150) {
    sendCommand("auto");
    autoMode = true;
    activeField = -1;
  }
  if (mouseX > 320 && mouseX < 420 && mouseY > 120 && mouseY < 150) {
    sendCommand("manual");
    autoMode = false;
    activeField = -1;
  }

  // Ползунок RPM (активен только в ручном режиме)
  if (!autoMode && mouseY > sliderY-15 && mouseY < sliderY+15 && mouseX > sliderX-10 && mouseX < sliderX + sliderW + 10) {
    sliderDragging = true;
    updateSlider();
  }

  // Текстовые поля
  if (mouseX > fieldX && mouseX < fieldX + fieldW) {
    if (mouseY > fieldY_tempOff && mouseY < fieldY_tempOff + fieldH) activeField = 0;
    else if (mouseY > fieldY_tempOn && mouseY < fieldY_tempOn + fieldH) activeField = 1;
    else if (mouseY > fieldY_tempMax && mouseY < fieldY_tempMax + fieldH) activeField = 2;
    else if (mouseY > fieldY_fanMin && mouseY < fieldY_fanMin + fieldH) activeField = 3;
    else if (mouseY > fieldY_fanMax && mouseY < fieldY_fanMax + fieldH) activeField = 4;
    else activeField = -1;
  } else {
    activeField = -1;
  }
}

void mouseDragged() {
  if (sliderDragging) {
    updateSlider();
  }
}

void mouseReleased() {
  if (sliderDragging) {
    sliderDragging = false;
  }
}

void updateSlider() {
  float newVal = map(constrain(mouseX, sliderX, sliderX + sliderW), sliderX, sliderX + sliderW, sliderMin, sliderMax);
  int newRpm = int(newVal);
  if (newRpm != rpmValue && !autoMode) {
    rpmValue = newRpm;
    sendCommand("set_rpm " + rpmValue);
  }
}

// --- Обработка клавиатуры ---
void keyPressed() {
  if (activeField == -1) {
    if (key == 'r' || key == 'R') {
      if (connected) disconnectPort();
      connectToPort();
    }
    return;
  }

  if (key == ENTER || key == RETURN) {
    String cmd = "";
    if (activeField == 0) cmd = "set_temp_off " + tempOffText;
    else if (activeField == 1) cmd = "set_temp_on " + tempOnText;
    else if (activeField == 2) cmd = "set_temp_max " + tempMaxText;
    else if (activeField == 3) cmd = "set_fan_min " + fanMinText;
    else if (activeField == 4) cmd = "set_fan_max " + fanMaxText;
    if (!cmd.isEmpty()) sendCommand(cmd);
    activeField = -1;
  } else if (key == BACKSPACE) {
    if (activeField == 0 && tempOffText.length() > 0) tempOffText = tempOffText.substring(0, tempOffText.length()-1);
    else if (activeField == 1 && tempOnText.length() > 0) tempOnText = tempOnText.substring(0, tempOnText.length()-1);
    else if (activeField == 2 && tempMaxText.length() > 0) tempMaxText = tempMaxText.substring(0, tempMaxText.length()-1);
    else if (activeField == 3 && fanMinText.length() > 0) fanMinText = fanMinText.substring(0, fanMinText.length()-1);
    else if (activeField == 4 && fanMaxText.length() > 0) fanMaxText = fanMaxText.substring(0, fanMaxText.length()-1);
  } else if (key >= '0' && key <= '9') {
    if (activeField == 0) tempOffText += key;
    else if (activeField == 1) tempOnText += key;
    else if (activeField == 2) tempMaxText += key;
    else if (activeField == 3) fanMinText += key;
    else if (activeField == 4) fanMaxText += key;
  }
}

// --- Отправка команд ---
void sendCommand(String cmd) {
  if (connected && myPort != null) {
    myPort.write(cmd + "\n");
    lastAction = "Sent: " + cmd;
  } else {
    lastAction = "Not connected: " + cmd;
  }
}

// --- Приём данных ---
void serialEvent(Serial p) {
  String data = p.readString().trim();
  if (data.length() == 0) return;
  String[] parts = data.split("\\s+");
  for (int i = 0; i < parts.length; i++) {
    if (parts[i].equals("RPM:")) currentRPM = int(parts[i+1]);
    if (parts[i].equals("Set:")) currentSet = int(parts[i+1]);
    if (parts[i].equals("PWM:")) currentPWM = int(parts[i+1]);
  }
}

// ============ Чтение температуры CPU из OpenHardwareMonitor ============
void updateCpuTemp() {
  while (true) {
    try {
      String cmd = "wmic /namespace:\\\\root\\OpenHardwareMonitor path Sensor where \"SensorType='Temperature'\" get Name,Value /format:list";
      Process p = Runtime.getRuntime().exec(cmd);
      BufferedReader reader = new BufferedReader(new InputStreamReader(p.getInputStream()));
      String line;
      String sensorName = "";
      float tempValue = -1;
      boolean found = false;
      float maxCoreTemp = -999;

      while ((line = reader.readLine()) != null) {
        line = line.trim();
        if (line.startsWith("Name=")) {
          sensorName = line.substring(5);
          tempValue = -1;
        } else if (line.startsWith("Value=") && !sensorName.isEmpty()) {
          tempValue = float(line.substring(6));
          if (sensorName.equals("CPU Package")) {
            cpuTemp = int(tempValue);
            cpuTempValid = true;
            lastAction = "CPU temp (Package): " + cpuTemp;
            found = true;
            break;
          } else if (sensorName.startsWith("CPU Core")) {
            if (tempValue > maxCoreTemp) {
              maxCoreTemp = tempValue;
            }
          }
        }
      }

      if (!found && maxCoreTemp > -999) {
        cpuTemp = int(maxCoreTemp);
        cpuTempValid = true;
        lastAction = "CPU max core temp: " + cpuTemp;
        found = true;
      }

      if (!found) {
        cpuTempValid = false;
        lastAction = "CPU temp sensor not found";
      }
    } catch (Exception e) {
      cpuTempValid = false;
      lastAction = "CPU temp error: " + e.getMessage();
    }
    delay(5000);
  }
}
