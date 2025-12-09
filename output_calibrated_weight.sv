// Generate tare, calibration, raw input, output, and decimal location 
module output_calibrated_weight(input clk, 
                                input signed [23:0] TARE,
                                input signed [23:0] CALIBRATE_VAL,
                                input signed [23:0] RAW_VAL,
                                output [24:0] CALIBRATED_OUTPUT,
                                output [2:0] DP_LOC
    );

    // Sets up 39 signed bits for calibration, output, tare and input and sets all of them as 0
    reg signed [38:0] big_calibrated_output, big_tare, big_calibrate, big_raw = 0;

    // Set the calibration mass at 39 bits and set it to 5
    // Change depending on the calibration used
    parameter signed [38:0]calibration_mass = 5;

    // The next steps require sequential logic
    always@(posedge clk) begin
        big_tare <= TARE; // Put 24-bit TARE into 39 bit register to make room for later subtraction/multiplication
        big_calibrate <= CALIBRATE_VAL; // Put 24-bit Calibration into 39 bit register to make room for later math
        big_raw <= RAW_VAL; // Put 24-bit raw input into 39 bit register to make room for later math

        //Finally, calculate the weight using the 39 bit values
        big_calibrated_output <= ((big_raw-big_tare)*(calibration_mass*10000))/(big_calibrate);
    end

    // If negative, do the 1's compliment, which is close enough to the 2's compliment given the noise in the system
    assign CALIBRATED_OUTPUT = big_calibrated_output[24]?{1'b1, ~big_calibrated_output[23:0]}:big_calibrated_output[24:0];
    assign DP_LOC = 4; //10,000 = 10^4 // Decimal point should be at location 4

endmodule