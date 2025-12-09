module top_module(
    input wire clk_100MHz,
    input wire DOUT,
    input wire tare_button,       
    input wire calib_button,      
    output wire PD_SCK,
    output wire [7:0] SEG,
    output wire [7:0] AN,
    output reg TX
);

    // Raw HX711 output init
    wire signed [23:0] RAW_VAL;
    wire DATA_VALID; 

    // Outputs from calibration module init
    wire signed [24:0] CALIBRATED_OUTPUT;
    wire [2:0] DP_LOC;

    // Tare + calibration values used in tare and calibration modules
    wire signed [23:0] TARE;
    wire signed [23:0] CALIBRATE_VAL;

    // HX711 reader init
    hx711_data_module HX711(
        clk_100MHz, 
        DOUT, 
        PD_SCK, 
        RAW_VAL, 
        DATA_VALID
    );

    // Generate calibrated weight init
    output_calibrated_weight CALC_WEIGHT(
        clk_100MHz, 
        TARE, 
        CALIBRATE_VAL, 
        RAW_VAL, 
        CALIBRATED_OUTPUT, 
        DP_LOC
    );

    // 7-segment display driver init
    signed_bcd_driver DISPLAY(
        clk_100MHz, 
        CALIBRATED_OUTPUT, 
        SEG, 
        AN
    );

    // Button input for tare and calibration init
    get_tare_and_calibration GET_TARE_CAL(
        clk_100MHz, 
        tare_button, 
        calib_button, 
        DATA_VALID, 
        RAW_VAL, 
        TARE,
        CALIBRATE_VAL
    );

    // Proof-of-concept UART output
    UARTtx UART(
        clk_100MHz, 
        CALIBRATED_OUTPUT, 
        TX
    );

endmodule

