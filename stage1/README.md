# Stage 1 #

### Description ###

###### Part1:

Develop an application that periodically reads the brightness sensor every T seconds. If the brightness value is smaller than a certain threshold B, the application should turn on the blue LED, else turn it off. Let T = 1 second and B = 40 (this value is appropriate for tests in typical lab conditions, by covering/uncovering the brightness sensor with your hand or a piece of paper).

**Note:** Do not invoke the LED component unless you have to, i.e., turn the blue LED on/off only when moving from the "bright" state to the "dark" state and vice versa.

###### Part 2:

Extend the application so that it sends the brightness values it reads over the serial port, and so that it adjusts the sampling period T when it receives a corresponding request from the serial port. You also have to develop a program that runs on the PC, which can be used to set the sampling rate of the application on the node, as well as to observe its sensor readings.
