// TrainBrain v3 - Unified E-ink Display with Rotary Encoder
// For Arduino Nano 33 BLE with E-ink display (250x122px)

#include <ArduinoBLE.h>
#include <GxEPD2_BW.h>
#include <Fonts/FreeMonoBold9pt7b.h>
#include <Fonts/FreeSansBold12pt7b.h>
#include <Fonts/FreeSans9pt7b.h>
#include <Fonts/FreeMono9pt7b.h>
#include <Fonts/FreeSerif9pt7b.h>
#include <Fonts/TomThumb.h>  // Added for bottom section

// Include icon bitmaps
#include "icons.h"

// Display definitions - using 2.13" e-ink display
GxEPD2_BW<GxEPD2_213_BN, GxEPD2_213_BN::HEIGHT> display(GxEPD2_213_BN(/*CS=*/ 10, /*DC=*/ 8, /*RST=*/ 9, /*BUSY=*/ 7)); // DEPG0213BN 122x250

// Font configuration - centralized for easy changes
struct FontConfig {
  const GFXfont* headerFont;
  const GFXfont* modeWorkoutFont;
  const GFXfont* modeVocabWordFont;
  const GFXfont* modeVocabTranslationFont;
  const GFXfont* modeVocabSentenceFont;
  const GFXfont* bottomFont;
} fonts;

// Display regions for partial updates
#define REGION_FULL      0xFF
#define REGION_HEADER    0x01
#define REGION_CONTENT   0x02
#define REGION_BOTTOM    0x04

// Special mode values
#define MODE_WORKOUT     0
#define MODE_VOCABULARY  1
#define MODE_WELCOME     255  // Special value to show welcome screen

// Rotary encoder pins
#define ROTARY_CLK       2    // Clock pin
#define ROTARY_DT        3    // Data pin
#define ROTARY_SW        6    // Switch pin

// Encoder state variables
volatile int lastClkState;
volatile int counter = 0;
volatile unsigned long lastButtonPress = 0;
volatile bool buttonPressed = false;

// BLE Service and Characteristics
BLEService displayService("19B10000-E8F2-537E-4F6C-D104768A1214");

// Line content characteristics
BLEStringCharacteristic line1Characteristic("19B10001-E8F2-537E-4F6C-D104768A1214", BLERead | BLEWrite, 32);
BLEStringCharacteristic line2Characteristic("19B10002-E8F2-537E-4F6C-D104768A1214", BLERead | BLEWrite, 32);
BLEStringCharacteristic line3Characteristic("19B10003-E8F2-537E-4F6C-D104768A1214", BLERead | BLEWrite, 128);

// Display control characteristics
BLEByteCharacteristic refreshRegionCharacteristic("19B10004-E8F2-537E-4F6C-D104768A1214", BLERead | BLEWrite);
BLEByteCharacteristic rotaryValueCharacteristic("19B10005-E8F2-537E-4F6C-D104768A1214", BLERead | BLENotify);
BLEBoolCharacteristic buttonPressCharacteristic("19B10006-E8F2-537E-4F6C-D104768A1214", BLERead | BLENotify);
BLEByteCharacteristic modeCharacteristic("19B10007-E8F2-537E-4F6C-D104768A1214", BLERead | BLEWrite);

// App state variables
String line1Text = "";
String line2Text = "";
String line3Text = "";
bool isConnected = false;
byte currentMode = 0;    // 0 = Workout mode, 1 = Vocabulary mode
bool showingWelcomeScreen = true;
bool inQuizMode = false;
byte previousMode = 255; // Track previous mode to detect mode changes
bool modeJustChanged = false; // Flag to force full refresh on mode change

// Workout counters
int pushUpCount = 0;
int pullUpCount = 0;

// Debug message for bottom section
String debugMessage = "Ready";

// Display update control
unsigned long lastRefreshTime = 0;
const unsigned long REFRESH_DEBOUNCE_TIME = 200; // Reduced to 200ms for faster response
const unsigned long BUTTON_DEBOUNCE_TIME = 150;  // Reduced to 150ms for faster response

// Partial update regions (adjusted for optimal display)
const int HEADER_X = 0;
const int HEADER_Y = 0;
const int HEADER_W = 250;
const int HEADER_H = 22;

const int CONTENT_X = 0;
const int CONTENT_Y = 22;
const int CONTENT_W = 250;
const int CONTENT_H = 80;

const int BOTTOM_X = 0;
const int BOTTOM_Y = 102;
const int BOTTOM_W = 250;
const int BOTTOM_H = 20;

// Initialize the display with error handling
bool initializeDisplay() {
  display.init(115200, true, 2, false);
  display.setRotation(1); // Landscape mode (250x122)
  display.setTextColor(GxEPD_BLACK);
  
  // Set up fonts
  fonts.headerFont = &FreeMono9pt7b;
  fonts.modeWorkoutFont = &FreeMono9pt7b; // Changed to FreeMono9pt7b as requested
  fonts.modeVocabWordFont = &FreeSerif9pt7b;
  fonts.modeVocabTranslationFont = &FreeMono9pt7b;
  fonts.modeVocabSentenceFont = &TomThumb;
  fonts.bottomFont = &TomThumb;
  
  return true;
}

// Handle rotary encoder interrupts with faster response
void handleEncoderRotation() {
  int clkState = digitalRead(ROTARY_CLK);
  int dtState = digitalRead(ROTARY_DT);
  
  // If CLK changed (transition from HIGH to LOW)
  if (clkState != lastClkState && clkState == LOW) {
    // Check direction by reading DT
    if (dtState != clkState) {
      // Clockwise rotation (right)
      counter++;
      
      if (showingWelcomeScreen) {
        return; // No action on welcome screen
      }
      
      if (currentMode == MODE_WORKOUT) { 
        // Right = Push-up increment
        pushUpCount++;
        debugMessage = "Push-up +1";
        
        // Immediate UI update without debounce
        updateWorkoutDisplay(REGION_CONTENT);
        updateBottomRegion();
        
        // Notify app of the increment
        rotaryValueCharacteristic.writeValue(1); // 1 = right/push-up increment
      } else { 
        // Vocabulary - Right = Next word
        debugMessage = "Next word";
        updateBottomRegion();
        
        // Notify app to go to next word
        rotaryValueCharacteristic.writeValue(1); // 1 = right/next word
      }
    } else {
      // Counter-clockwise rotation (left)
      counter--;
      
      if (showingWelcomeScreen) {
        return; // No action on welcome screen
      }
      
      if (currentMode == MODE_WORKOUT) { 
        // Left = Pull-up increment
        pullUpCount++;
        debugMessage = "Pull-up +1";
        
        // Immediate UI update without debounce
        updateWorkoutDisplay(REGION_CONTENT);
        updateBottomRegion();
        
        // Notify app of the increment
        rotaryValueCharacteristic.writeValue(2); // 2 = left/pull-up increment
      } else { 
        // Vocabulary - Left = Show translation
        debugMessage = "Show translation";
        updateBottomRegion();
        
        // Notify app to show translation
        rotaryValueCharacteristic.writeValue(2); // 2 = left/show translation
      }
    }
  }
  lastClkState = clkState;
}

// Handle button press interrupt with faster response
void handleButtonPress() {
  unsigned long currentTime = millis();
  
  // Reduced debounce time for faster response
  if (currentTime - lastButtonPress > BUTTON_DEBOUNCE_TIME) {
    buttonPressed = true;
    
    if (showingWelcomeScreen) {
      return; // No action on welcome screen
    }
    
    // Send button press notification to app - immediate notification
    buttonPressCharacteristic.writeValue(1);
    
    if (currentMode == MODE_WORKOUT) {
      // Reset workout counters
      pushUpCount = 0;
      pullUpCount = 0;
      debugMessage = "Counters reset";
      
      // Immediate UI update
      updateWorkoutDisplay(REGION_CONTENT);
      updateBottomRegion();
    } else {
      // Toggle quiz mode in vocabulary mode
      inQuizMode = !inQuizMode;
      debugMessage = inQuizMode ? "Quiz started" : "Quiz stopped";
      updateBottomRegion();
    }
    
    lastButtonPress = currentTime;
    
    // Reset button state after brief delay
    delay(50); // Reduced from 100ms to 50ms
    buttonPressCharacteristic.writeValue(0);
  }
}

// Update the bottom region with debug message and arrows
void updateBottomRegion() {
  display.setPartialWindow(BOTTOM_X, BOTTOM_Y, BOTTOM_W, BOTTOM_H);
  display.firstPage();
  do {
    display.fillScreen(GxEPD_WHITE);
    
    // Left arrow
    display.drawBitmap(5, BOTTOM_Y + 4, arrowLeftIcon, 12, 12, GxEPD_BLACK);
    
    // Right arrow
    display.drawBitmap(BOTTOM_W - 17, BOTTOM_Y + 4, arrowRightIcon, 12, 12, GxEPD_BLACK);
    
    // Debug message in the center
    display.setFont(fonts.bottomFont);
    
    // Center the debug message
    int16_t x1, y1;
    uint16_t w, h;
    display.getTextBounds(debugMessage, 0, 0, &x1, &y1, &w, &h);
    int x = (BOTTOM_W - w) / 2;
    
    display.setCursor(x, BOTTOM_Y + 14);
    display.print(debugMessage);
    
  } while (display.nextPage());
}

// Draw the welcome screen
void drawWelcomeScreen() {
  display.setFullWindow();
  display.firstPage();
  do {
    display.fillScreen(GxEPD_WHITE);
    
    // Draw TrainBrain logo
    display.drawBitmap((BOTTOM_W - 60) / 2, 10, logoImage, 60, 60, GxEPD_BLACK);
    
    // Draw TrainBrain title
    display.setFont(&FreeSansBold12pt7b);
    int16_t x1, y1;
    uint16_t w, h;
    String title = "TrainBrain";
    display.getTextBounds(title, 0, 0, &x1, &y1, &w, &h);
    display.setCursor((BOTTOM_W - w) / 2, 85);
    display.print(title);
    
    // Draw connection status
    display.setFont(&FreeSans9pt7b);
    String statusText = isConnected ? "Connected!" : "Waiting for connection...";
    display.getTextBounds(statusText, 0, 0, &x1, &y1, &w, &h);
    display.setCursor((BOTTOM_W - w) / 2, 110);
    display.print(statusText);
    
  } while (display.nextPage());
}

// Update the header region (no divider line)
void updateHeaderRegion() {
  display.setPartialWindow(HEADER_X, HEADER_Y, HEADER_W, HEADER_H);
  display.firstPage();
  do {
    display.fillScreen(GxEPD_WHITE);
    
    // Mode icon on left
    display.drawBitmap(5, 2, currentMode == MODE_WORKOUT ? workoutIcon : vocabIcon, MODE_ICON_WIDTH, MODE_ICON_HEIGHT, GxEPD_BLACK);
    
    // Mode text 
    display.setFont(fonts.headerFont);
    display.setCursor(30, 16);
    display.print(currentMode == MODE_WORKOUT ? "Workout" : "Vocabulary");
    
    // Connection icon on right
    display.drawBitmap(230, 2, isConnected ? bluetoothIcon : disconnectIcon, BLUETOOTH_ICON_WIDTH, BLUETOOTH_ICON_HEIGHT, GxEPD_BLACK);
    
  } while (display.nextPage());
}

// Update workout display
void updateWorkoutDisplay(byte region) {
  if (region & REGION_CONTENT) {
    // Update the content region with workout counters
    display.setPartialWindow(CONTENT_X, CONTENT_Y, CONTENT_W, CONTENT_H);
    display.firstPage();
    do {
      display.fillScreen(GxEPD_WHITE);
      
      // Push-ups counter - positioned closer together
      display.setFont(fonts.modeWorkoutFont);
      display.setCursor(10, CONTENT_Y + 30);
      display.print("PUSH-UPS:");
      
      // Position counter closer to the label
      String pushupStr = String(pushUpCount);
      int16_t x1, y1;
      uint16_t w, h;
      display.getTextBounds(pushupStr, 0, 0, &x1, &y1, &w, &h);
      display.setCursor(140, CONTENT_Y + 30);  // Moved closer (was 150)
      display.print(pushupStr);
      
      // Pull-ups counter
      display.setCursor(10, CONTENT_Y + 60);
      display.print("PULL-UPS:");
      
      // Position counter closer to the label
      String pullupStr = String(pullUpCount);
      display.getTextBounds(pullupStr, 0, 0, &x1, &y1, &w, &h);
      display.setCursor(140, CONTENT_Y + 60);  // Moved closer (was 150)
      display.print(pullupStr);
      
    } while (display.nextPage());
  }
}

// Update vocabulary display
void updateVocabularyDisplay(byte region) {
  if (region & REGION_CONTENT) {
    // Update the content region with word and translation
    display.setPartialWindow(CONTENT_X, CONTENT_Y, CONTENT_W, CONTENT_H);
    display.firstPage();
    do {
      display.fillScreen(GxEPD_WHITE);
      
      // Word - using vocab word font
      display.setFont(fonts.modeVocabWordFont);
      display.setCursor(10, CONTENT_Y + 25);
      display.print(line1Text);
      
      // Translation - using vocab translation font
      display.setFont(fonts.modeVocabTranslationFont);
      display.setCursor(10, CONTENT_Y + 50);
      display.print(line2Text);
      
      // Example sentence - using vocab sentence font
      if (!line3Text.isEmpty()) {
        display.setFont(fonts.modeVocabSentenceFont);
        
        // Wrap text for the sentence (simplified)
        String sentence = line3Text;
        int yPos = CONTENT_Y + 65;
        int lineHeight = 10;
        int maxWidth = CONTENT_W - 20;
        int maxChars = 50; // Approximate chars per line based on font
        
        // This is a very simplified text wrapping approach
        int strLen = sentence.length();
        int startPos = 0;
        
        while (startPos < strLen) {
          int endPos = min(startPos + maxChars, strLen);
          
          // Try to find a space to break the line
          if (endPos < strLen) {
            int lastSpace = sentence.lastIndexOf(' ', endPos);
            if (lastSpace > startPos) {
              endPos = lastSpace + 1;
            }
          }
          
          String line = sentence.substring(startPos, endPos);
          display.setCursor(10, yPos);
          display.print(line);
          
          startPos = endPos;
          yPos += lineHeight;
          
          // Check if we've run out of space
          if (yPos > CONTENT_Y + CONTENT_H - 5) {
            break;
          }
        }
      }
      
    } while (display.nextPage());
  }
}

// Full display update based on current mode
void updateFullDisplay() {
  // Full screen refresh - important for mode changes
  display.setFullWindow();
  display.firstPage();
  
  do {
    display.fillScreen(GxEPD_WHITE);
    
    // Draw the header
    // Mode icon on left
    display.drawBitmap(5, 2, currentMode == MODE_WORKOUT ? workoutIcon : vocabIcon, MODE_ICON_WIDTH, MODE_ICON_HEIGHT, GxEPD_BLACK);
    
    // Mode text 
    display.setFont(fonts.headerFont);
    display.setCursor(30, 16);
    display.print(currentMode == MODE_WORKOUT ? "Workout" : "Vocabulary");
    
    // Connection icon on right
    display.drawBitmap(230, 2, isConnected ? bluetoothIcon : disconnectIcon, BLUETOOTH_ICON_WIDTH, BLUETOOTH_ICON_HEIGHT, GxEPD_BLACK);
    
    // Draw content based on mode
    if (currentMode == MODE_WORKOUT) {
      // Push-ups counter
      display.setFont(fonts.modeWorkoutFont);
      display.setCursor(10, CONTENT_Y + 30);
      display.print("PUSH-UPS:");
      
      // Position counter closer to the label
      String pushupStr = String(pushUpCount);
      display.setCursor(140, CONTENT_Y + 30);
      display.print(pushupStr);
      
      // Pull-ups counter
      display.setCursor(10, CONTENT_Y + 60);
      display.print("PULL-UPS:");
      
      // Position counter closer to the label
      String pullupStr = String(pullUpCount);
      display.setCursor(140, CONTENT_Y + 60);
      display.print(pullupStr);
    } else {
      // Word - using vocab word font
      display.setFont(fonts.modeVocabWordFont);
      display.setCursor(10, CONTENT_Y + 25);
      display.print(line1Text);
      
      // Translation - using vocab translation font
      display.setFont(fonts.modeVocabTranslationFont);
      display.setCursor(10, CONTENT_Y + 50);
      display.print(line2Text);
      
      // Example sentence - using vocab sentence font
      if (!line3Text.isEmpty()) {
        display.setFont(fonts.modeVocabSentenceFont);
        display.setCursor(10, CONTENT_Y + 65);
        
        // Simple display - full wrapping not needed for full refresh
        // Just truncate if needed
        if (line3Text.length() > 50) {
          display.print(line3Text.substring(0, 47) + "...");
        } else {
          display.print(line3Text);
        }
      }
    }
    
    // Draw bottom section
    // Left arrow
    display.drawBitmap(5, BOTTOM_Y + 4, arrowLeftIcon, 12, 12, GxEPD_BLACK);
    
    // Right arrow
    display.drawBitmap(BOTTOM_W - 17, BOTTOM_Y + 4, arrowRightIcon, 12, 12, GxEPD_BLACK);
    
    // Debug message in the center
    display.setFont(fonts.bottomFont);
    
    // Center the debug message
    int16_t x1, y1;
    uint16_t w, h;
    display.getTextBounds(debugMessage, 0, 0, &x1, &y1, &w, &h);
    int x = (BOTTOM_W - w) / 2;
    
    display.setCursor(x, BOTTOM_Y + 14);
    display.print(debugMessage);
    
  } while (display.nextPage());
  
  modeJustChanged = false; // Reset the flag
}

void setup() {
  Serial.begin(9600);
  
  // Initialize rotary encoder pins
  pinMode(ROTARY_CLK, INPUT_PULLUP);
  pinMode(ROTARY_DT, INPUT_PULLUP);
  pinMode(ROTARY_SW, INPUT_PULLUP);
  
  // Read initial state of CLK pin
  lastClkState = digitalRead(ROTARY_CLK);
  
  // Initialize display
  if (!initializeDisplay()) {
    Serial.println("Display initialization failed!");
    while (1); // Don't proceed if display init fails
  }
  
  // Initialize BLE
  if (!BLE.begin()) {
    Serial.println("BLE initialization failed!");
    // Show error on display
    while (1); // Don't proceed if BLE init fails
  }
  
  // Set up BLE service and characteristics
  BLE.setDeviceName("TrainBrain");
  BLE.setLocalName("TrainBrain");
  BLE.setAdvertisedService(displayService);
  
  // Add characteristics to service
  displayService.addCharacteristic(line1Characteristic);
  displayService.addCharacteristic(line2Characteristic);
  displayService.addCharacteristic(line3Characteristic);
  displayService.addCharacteristic(refreshRegionCharacteristic);
  displayService.addCharacteristic(rotaryValueCharacteristic);
  displayService.addCharacteristic(buttonPressCharacteristic);
  displayService.addCharacteristic(modeCharacteristic);
  
  // Add service and advertise
  BLE.addService(displayService);
  BLE.advertise();
  
  // Initial values
  line1Characteristic.writeValue("");
  line2Characteristic.writeValue("");
  line3Characteristic.writeValue("");
  refreshRegionCharacteristic.writeValue(REGION_FULL);
  rotaryValueCharacteristic.writeValue(0);
  buttonPressCharacteristic.writeValue(false);
  modeCharacteristic.writeValue(0);
  
  // Set debug message
  debugMessage = "Welcome to TrainBrain";
  
  // Show welcome screen
  drawWelcomeScreen();
  
  Serial.println("Setup complete, TrainBrain ready");
}

void loop() {
  // Poll BLE events
  BLE.poll();
  
  // Handle rotary encoder manually - check more frequently for fast response
  handleEncoderRotation();
  
  // Check button state manually - check more frequently for fast response
  if (digitalRead(ROTARY_SW) == LOW && !buttonPressed) {
    handleButtonPress();
  } else if (digitalRead(ROTARY_SW) == HIGH) {
    buttonPressed = false;
  }
  
  // Connection handling
  BLEDevice central = BLE.central();
  if (central && central.connected()) {
    if (!isConnected) {
      // Just connected
      isConnected = true;
      if (showingWelcomeScreen) {
        // Update welcome screen with connected status
        drawWelcomeScreen();
      } else {
        updateFullDisplay();
      }
      Serial.println("Connected to central device");
      debugMessage = "Connected";
    }
    
    // Check for characteristic updates
    if (line1Characteristic.written()) {
      line1Text = line1Characteristic.value();
      if (currentMode == MODE_VOCABULARY && !showingWelcomeScreen) {
        updateVocabularyDisplay(REGION_CONTENT);
      }
    }
    
    if (line2Characteristic.written()) {
      line2Text = line2Characteristic.value();
      if (currentMode == MODE_VOCABULARY && !showingWelcomeScreen) {
        updateVocabularyDisplay(REGION_CONTENT);
      }
    }
    
    if (line3Characteristic.written()) {
      line3Text = line3Characteristic.value();
      if (currentMode == MODE_VOCABULARY && !showingWelcomeScreen) {
        updateVocabularyDisplay(REGION_CONTENT);
      }
    }
    
    if (refreshRegionCharacteristic.written()) {
      byte region = refreshRegionCharacteristic.value();
      
      // Reduced debounce time for faster updates
      if (millis() - lastRefreshTime >= REFRESH_DEBOUNCE_TIME) {
        if (region == REGION_FULL || modeJustChanged) {
          if (showingWelcomeScreen) {
            drawWelcomeScreen();
          } else {
            updateFullDisplay();
          }
        } else if (!showingWelcomeScreen) {
          if (region & REGION_HEADER) {
            updateHeaderRegion();
          }
          
          if (region & REGION_CONTENT) {
            if (currentMode == MODE_WORKOUT) {
              updateWorkoutDisplay(REGION_CONTENT);
            } else {
              updateVocabularyDisplay(REGION_CONTENT);
            }
          }
          
          if (region & REGION_BOTTOM) {
            updateBottomRegion();
          }
        }
        
        lastRefreshTime = millis();
      }
    }
    
    if (modeCharacteristic.written()) {
      byte newMode = modeCharacteristic.value();
      
      if (newMode == MODE_WELCOME) {
        // Special value to trigger welcome screen
        showingWelcomeScreen = true;
        drawWelcomeScreen();
        Serial.println("Showing welcome screen");
        debugMessage = "Welcome screen";
      } else if (newMode != currentMode || showingWelcomeScreen) {
        // Save the previous mode
        previousMode = currentMode;
        
        // Update to new mode
        currentMode = newMode;
        showingWelcomeScreen = false;
        debugMessage = (currentMode == MODE_WORKOUT) ? "Workout mode" : "Vocabulary mode";
        
        // Set flag for mode change
        modeJustChanged = true;
        
        // Do a full display refresh immediately on mode change
        updateFullDisplay();
        
        Serial.println("Mode changed");
      }
    }
  } else if (isConnected) {
    // Just disconnected
    isConnected = false;
    showingWelcomeScreen = true;
    drawWelcomeScreen();
    Serial.println("Disconnected from central device");
    debugMessage = "Disconnected";
    
    // Reset BLE advertising
    BLE.advertise();
  }
  
  // Very small delay to prevent tight loops but maintain fast response
  delay(5);
}