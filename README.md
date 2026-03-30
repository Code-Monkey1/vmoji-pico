# vmoji-pico
Volumetric Display for the Raspberry Pi Pico 1.

## Quick Start (VS Code)

Use the **Raspberry Pi Pico extension** to prepare the environment (install the "pico-sdk" SDK locally).

### Building
Then, from the extension, you can click "Compile Project".  

### Flashing
If not in bootloader mode already, reconnect the Raspberry Pi Pico while pressing down on the bootloader button.  
You should now see it as a "USB device" in your file explorer.  
Copy/paste the build .uf2 output file into that USB device to flash the device.

The device will restart automatically and run the program you flashed.


