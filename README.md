This project implements a fully functional FPGA-based digital scale on the Digilent Nexys A7. The system interfaces with an HX711 24-bit ADC module to acquire load-cell readings, 
applies tare and calibration factors, converts the raw data into fixed point grams, and drives a four digit 7-segment display using a custom BCD output driver. Core modules include the 
HX711 serial reader, a calibration/tare handler, a real time weight calculator, a signed-BCD display encoder, and a UART transmitter for optional serial output. The system supports both 
interactive use and continuous measurement.

The design is fully modular, with each SystemVerilog file representing a distinct hardware block in the data path. The HX711 reader implements timing-accurate sampling, the calibration
module computes offset and scale factors, and the output module produces human-readable weight values. and demonstrates embedded digital design principles including FSM control, signal 
synchronization, arithmetic pipelines, and hardware level debugging. 
