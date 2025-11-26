This FPGA-based Digital Scale project implements a complete load-cell measurement system on the Nexys A7-100T board using the HX711 24-bit ADC module. The design includes tare 
and calibration logic, real-time data processing, and a custom multi-digit 7-segment display driver written entirely in SystemVerilog. The system captures high-resolution weight 
data, filters and stabilizes readings, and presents them cleanly on the display while maintaining precise timing and reliable state-machine control.

Future revisions of this project will integrate UART communication to transmit live weight readings to a host computer for data logging, debugging, and extended functionality.
This addition will allow the scale to output measurements in real time via a serial terminal or external application, creating a bridge between hardware-level sensing and 
higher-level data analysis. The project serves as a foundation for more advanced embedded-FPGA instrumentation systems and highlights modular digital design practices.
