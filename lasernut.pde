import processing.video.*;
import java.util.ArrayList; // Import ArrayList for storing lines

Capture video;
String[] cameras;
int selectedCameraIndex = 0;
PImage lastFrame; // Stores the last valid frame
float brightnessThreshold = 200; // Minimum brightness for detection
PVector previousPoint = null; // Tracks the previous laser point for drawing lines
ArrayList<PVector[]> lines = new ArrayList<>(); // List to store lines as pairs of points
boolean showCamera = true; // Flag to toggle camera feed on/off
boolean greenMode = false; // Flag for "G mode" to use only the green channel

SecondWindow secondWindow; // Reference to the second window
Slider thresholdSlider; // Slider for adjusting the brightness threshold
Slider lineBrightnessSlider; // Slider for adjusting line brightness
Slider keystoneSlider; // Slider for adjusting keystone effect

// Variables for the inclusion zone
boolean isDragging = false; // Whether the user is currently dragging
int zoneX1 = -1, zoneY1 = -1, zoneX2 = -1, zoneY2 = -1; // Zone boundaries
int lineColorR = 255, lineColorG = 255, lineColorB = 255;

void setup() {
  size(640, 480);
  surface.setResizable(true);

  // Create the sliders
  thresholdSlider = new Slider(10, height - 50, 200, 20, 0, 255, (int) brightnessThreshold);
  lineBrightnessSlider = new Slider(220, height - 50, 200, 20, 0, 255, 255); // Full brightness by default
  keystoneSlider = new Slider(430, height - 50, 200, 20, -1000, 1000, 0); // Keystone effect slider (0-1000)

  // List available cameras
  cameras = Capture.list();
  println("Available Cameras:");
  for (int i = 0; i < cameras.length; i++) {
    println("[" + i + "] " + cameras[i]);
  }

  if (cameras.length > 0) {
    selectedCameraIndex = 0; // Choose the first camera by default
    video = new Capture(this, cameras[selectedCameraIndex]);
    video.start();
  } else {
    println("No cameras found!");
  }

  // Create the second window
  secondWindow = new SecondWindow(this);
  openReadme();
}



void openReadme() {
  String path = sketchPath("data/Readme.txt");
  try {
    java.awt.Desktop.getDesktop().open(new java.io.File(path));
    println("Readme.txt opened successfully.");
  } catch (Exception e) {
    println("Failed to open Readme.txt: " + e.getMessage());
  }
}




void draw() {
  // Clear the canvas for each frame.
  background(0);


  // === Process and display the camera feed ===
  if (showCamera && video != null && video.available()) {
    video.read();
    lastFrame = video.get();

    // If green mode is active, isolate the green channel.
    if (greenMode && lastFrame != null) {
      lastFrame.loadPixels();
      for (int i = 0; i < lastFrame.pixels.length; i++) {
        color c = lastFrame.pixels[i];
        float greenVal = green(c);  // get green channel value (0-255)
        lastFrame.pixels[i] = color(0, greenVal, 0);  // erase red and blue channels
      }
      lastFrame.updatePixels();
    }
  }

  if (showCamera && lastFrame != null) {
    // Display the camera image scaled to the current window size.
    image(lastFrame, 0, 0, width, height);
  }

  // === Draw the previously captured laser lines ===
  synchronized (lines) {
    stroke(0, 255, 0);  // green lines
    strokeWeight(2);
    for (PVector[] ln : lines) {
      // Scale line endpoints from the native 640x480 size to the current window size.
      float x1 = ln[0].x * ((float) width / 640);
      float y1 = ln[0].y * ((float) height / 480);
      float x2 = ln[1].x * ((float) width / 640);
      float y2 = ln[1].y * ((float) height / 480);
      line(x1, y1, x2, y2);
    }
  }

  // === Draw the inclusion zone (green rectangle) on top of the feed ===
  if (zoneX1 >= 0 && zoneY1 >= 0 && zoneX2 >= 0 && zoneY2 >= 0) {
    noFill();
    stroke(0, 255, 0);
    strokeWeight(2);
    rect(zoneX1, zoneY1, zoneX2 - zoneX1, zoneY2 - zoneY1);
  }

  // === Update the brightness threshold based on the slider ===
  brightnessThreshold = thresholdSlider.getValue();
  // Print the current threshold to the console for debugging.
  println("Current brightness threshold: " + brightnessThreshold);

  // === Find the brightest point within the inclusion zone (if any) ===
  if (lastFrame != null) {
    PVector laserCenter = findBrightestPoint(lastFrame);
    if (laserCenter != null) {
      // Draw a red box around the detected region.
      noFill();
      stroke(255, 0, 0);
      strokeWeight(2);
      float boxX = laserCenter.x * ((float) width / 640);
      float boxY = laserCenter.y * ((float) height / 480);
      rect(boxX - 10, boxY - 10, 20, 20);
      // If we have a previous point, connect it to the current one with a line.
      if (previousPoint != null) {
        synchronized (lines) {
          lines.add(new PVector[] {previousPoint.copy(), laserCenter.copy()});
        }
      }
      previousPoint = laserCenter;
    } else {
      previousPoint = null;
    }
  }

  // === Draw all sliders with labels ===
  fill(255);
  textSize(14);
  textAlign(LEFT, CENTER);

  text("Brightness Threshold", thresholdSlider.x, thresholdSlider.y - 10);
  thresholdSlider.display();

  text("Line Brightness", lineBrightnessSlider.x, lineBrightnessSlider.y - 10);
  lineBrightnessSlider.display();

  text("Keystone Effect", keystoneSlider.x, keystoneSlider.y - 10);
  keystoneSlider.display();
}


// Apply the keystone effect to a point
PVector applyKeystone(PVector point, float keystoneStrength) {
  float centerX = width / 2.0;
  float centerY = height / 2.0;

  // Calculate the vertical displacement based on x-coordinate.
  float dx = point.x - centerX;
  float dy = point.y - centerY;

  // Keystone strength linearly increases with x from 0 to width.
  float taperFactor = map(point.x, 0, width, 0, keystoneStrength);

  // Apply the taper factor only to the vertical displacement.
  float scaledY = centerY + dy * (1.0 + taperFactor);

  return new PVector(point.x, scaledY); // X remains unchanged.
}

// Start defining the inclusion zone
void mousePressed() {
  if (mouseButton == LEFT) { // Only process left mouse button
    zoneX1 = mouseX;
    zoneY1 = mouseY;
    zoneX2 = -1; // Reset the second point until the drag is completed
    zoneY2 = -1;
    isDragging = true;
  }
}

// Dynamically update the inclusion zone while dragging
void mouseDragged() {
  if (isDragging) {
    zoneX2 = mouseX;
    zoneY2 = mouseY;
  }
}

// Finalize the inclusion zone when the mouse is released
void mouseReleased() {
  if (isDragging) {
    isDragging = false;

    // Ensure the rectangle is properly defined (top-left to bottom-right)
    if (zoneX2 < zoneX1) {
      int temp = zoneX1;
      zoneX1 = zoneX2;
      zoneX2 = temp;
    }
    if (zoneY2 < zoneY1) {
      int temp = zoneY1;
      zoneY1 = zoneY2;
      zoneY2 = temp;
    }

    println("Inclusion zone set: (" + zoneX1 + ", " + zoneY1 + ") to (" + zoneX2 + ", " + zoneY2 + ")");
  }
}


PVector findBrightestPoint(PImage frame) {
  frame.loadPixels();

  int brightestX = -1;
  int brightestY = -1;
  float maxBrightness = -1;

  // Define boundaries based on the inclusion zone (or the whole frame if unset)
  int startX = (zoneX1 >= 0) ? zoneX1 : 0;
  int startY = (zoneY1 >= 0) ? zoneY1 : 0;
  int endX = (zoneX2 >= 0) ? zoneX2 : frame.width;
  int endY = (zoneY2 >= 0) ? zoneY2 : frame.height;

  for (int y = startY; y < endY; y++) {
    for (int x = startX; x < endX; x++) {
      int index = x + y * frame.width;
      color pixelColor = frame.pixels[index];

      float brightnessValue;
      if (greenMode) {
        // When greenMode is active, use the green channel directly.
        brightnessValue = green(pixelColor);
      } else {
        // brightness() normally returns a value between 0 and 100.
        brightnessValue = brightness(pixelColor) * 2.55;
      }

      if (brightnessValue > brightnessThreshold && brightnessValue > maxBrightness) {
        maxBrightness = brightnessValue;
        brightestX = x;
        brightestY = y;
      }
    }
  }

  // Debug: log the maximum brightness value found over the scanned region
  println("Max brightness found in region: " + maxBrightness);

  if (brightestX != -1 && brightestY != -1) {
    return new PVector(brightestX, brightestY);
  }

  return null;
}






void keyPressed() {
  // Reset inclusion zone
  if (key == 'r' || key == 'R') {
    zoneX1 = zoneY1 = zoneX2 = zoneY2 = -1;
    println("Inclusion zone reset");
  }

  // Move lines in the second window
  if (keyCode == UP) {
    secondWindow.offsetY -= 10;
  } else if (keyCode == DOWN) {
    secondWindow.offsetY += 10;
  } else if (keyCode == LEFT) {
    secondWindow.offsetX -= 10;
  } else if (keyCode == RIGHT) {
    secondWindow.offsetX += 10;
  }

  // Camera switching
  if (key == 'n' || key == 'N') {
    if (video != null) {
      video.stop();
    }
    selectedCameraIndex = (selectedCameraIndex + 1) % cameras.length;
    video = new Capture(this, cameras[selectedCameraIndex]);
    video.start();
  }

  // Clear all lines
  if (key == 'c' || key == 'C') {
    synchronized (lines) {
      lines.clear();
    }
    println("Cleared all lines!");
  }

  // Toggle camera view
  if (key == 'b' || key == 'B') {
    showCamera = !showCamera;
    println("Camera view toggled: " + (showCamera ? "ON" : "OFF"));
  }

  // Toggle green mode
  if (key == 'g' || key == 'G') {
    greenMode = !greenMode;
    println("Green mode " + (greenMode ? "ON" : "OFF"));
  }

  // Scale wider in the X direction
  if (key == '>' || key == '.') {
    secondWindow.scaleX *= 1.01; // Increase X scale factor by 10%
    println("Scaled wider (X): " + secondWindow.scaleX);
  }

  // Scale narrower in the X direction
  if (key == '<' || key == ',') {
    secondWindow.scaleX *= 0.99; // Decrease X scale factor by 10%
    println("Scaled narrower (X): " + secondWindow.scaleX);
  }
}
public class SecondWindow extends PApplet {
  lasernut parent; // Reference to the main sketch (lasernut)
  float offsetX = 0, offsetY = 0;
  float scaleX = 1.0; // Scale factor for X direction
  float scaleFactor = 1.0; // Uniform scaling for both X and Y directions
  boolean showGrid = false;

  SecondWindow(lasernut parent) {
    this.parent = parent;
    PApplet.runSketch(new String[] {"SecondWindow"}, this);
  }

  public void settings() {
    size(400, 300);
  }

  public void setup() {
    surface.setResizable(true);
  }

  public void draw() {
    background(0);

    // Get keystone strength (0–1000 scaled to 0–1)
    float keystoneStrength = parent.keystoneSlider.getValue() / 1000.0;

    // Get line brightness from the slider
    int lineBrightness = parent.lineBrightnessSlider.getValue();

    // Draw the test grid if enabled
    if (showGrid) {
      drawTestGrid(keystoneStrength, lineBrightness);
    }

    // Access lines from the parent sketch
    ArrayList<PVector[]> mainLines;
    synchronized (parent.lines) {
      mainLines = new ArrayList<>(parent.lines);
    }

    // Use parent's RGB line colors
    int lineColorR = parent.lineColorR;
    int lineColorG = parent.lineColorG;
    int lineColorB = parent.lineColorB;

    // Set stroke color using RGB and brightness
    stroke(lineColorR, lineColorG, lineColorB, lineBrightness);
    strokeWeight(2);
    for (PVector[] line : mainLines) {
      PVector start = applyTransformations(line[0], keystoneStrength);
      PVector end = applyTransformations(line[1], keystoneStrength);
      line(start.x, start.y, end.x, end.y);
    }
  }

  public void keyPressed() {
    if (keyCode == UP) {
      offsetY -= 10;
    } else if (keyCode == DOWN) {
      offsetY += 10;
    } else if (keyCode == LEFT) {
      offsetX -= 10;
    } else if (keyCode == RIGHT) {
      offsetX += 10;
    }
    if (key == '+' || key == '=') { // Handle both '+' and '=' keys
      scaleFactor *= 1.05; // Increase the scale factor
      println("Scale increased: " + scaleFactor);
    } else if (key == '-' || key == '_') {
      scaleFactor /= 1.05; // Decrease the scale factor
      println("Scale decreased: " + scaleFactor);
    }
    // Toggle grid
    if (key == 't' || key == 'T') {
      showGrid = !showGrid;
    }

    // X-axis scaling
    if (key == '>' || key == '.') {
      scaleX *= 1.01;
      println("SecondWindow -> Scaled wider (X): " + scaleX);
    }
    if (key == '<' || key == ',') {
      scaleX *= 0.99;
      println("SecondWindow -> Scaled narrower (X): " + scaleX);
    }
  }

  // Apply transformations to points
  private PVector applyTransformations(PVector point, float keystoneStrength) {
    float centerX = width / 2.0;
    float centerY = height / 2.0;

    // Apply offsets
    float transformedX = point.x + offsetX;
    float transformedY = point.y + offsetY;

    // Apply keystone effect
    float dx = transformedX - centerX;
    float dy = transformedY - centerY;
    float horizontalFactor = map(transformedX, 0, width, 0, keystoneStrength);
    transformedY = centerY + dy * (1.0 + horizontalFactor);

    // Apply scaling for X direction
    transformedX = centerX + (transformedX - centerX) * scaleX;

    // Apply uniform scaling
    transformedX = centerX + (transformedX - centerX) * scaleFactor;
    transformedY = centerY + (transformedY - centerY) * scaleFactor;

    return new PVector(transformedX, transformedY);
  }

  private void drawTestGrid(float keystoneStrength, int lineBrightness) {
    stroke(255, lineBrightness);
    strokeWeight(1);
    for (int x = 0; x <= width; x += 20) {
      PVector start = applyTransformations(new PVector(x, 0), keystoneStrength);
      PVector end = applyTransformations(new PVector(x, height), keystoneStrength);
      line(start.x, start.y, end.x, end.y);
    }
    for (int y = 0; y <= height; y += 20) {
      PVector start = applyTransformations(new PVector(0, y), keystoneStrength);
      PVector end = applyTransformations(new PVector(width, y), keystoneStrength);
      line(start.x, start.y, end.x, end.y);
    }
  }
}



class Slider {
  int x, y, w, h; // Position and dimensions
  int minValue, maxValue, currentValue; // Range and current value

  Slider(int x, int y, int w, int h, int minValue, int maxValue, int currentValue) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
    this.minValue = minValue;
    this.maxValue = maxValue;
    this.currentValue = currentValue;
  }

  void display() {
    fill(100);
    rect(x, y, w, h); // Draw the slider background

    float knobX = map(currentValue, minValue, maxValue, x, x + w);
    fill(200);
    rect(knobX - 5, y, 10, h); // Draw the slider knob

    fill(255);
    textSize(12);
    textAlign(CENTER, CENTER);
    text(currentValue, knobX, y - 10); // Display the current value
  }

  int getValue() {
    if (mousePressed && mouseX >= x && mouseX <= x + w && mouseY >= y && mouseY <= y + h) {
      currentValue = (int) map(mouseX, x, x + w, minValue, maxValue); // Update value based on mouse position
      currentValue = constrain(currentValue, minValue, maxValue); // Constrain value to valid range
    }
    return currentValue;
  }
}
