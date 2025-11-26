
module top_module(
    input wire clk_100MHz,
    input wire DOUT,
    input wire tare_button,       
    input wire calib_button,      
    output wire PD_SCK,
    output wire [7:0] SEG,
    output wire [7:0] AN
);

    // Raw HX711 output init
    wire signed [23:0] RAW_VAL;
    wire DATA_VALID; 

    // Outputs from calibration module init
    wire signed [24:0] CALIBRATED_OUTPUT;
    wire [2:0] DP_LOC;

    // Tare + calibration values used in generate tare and calibration module
    wire signed [23:0] TARE;
    wire signed [23:0] CALIBRATE_VAL;

    // HX711 reader init
    hx711_data_module HX711(clk_100MHz, DOUT, PD_SCK, RAW_VAL, DATA_VALID);

    // Generate calibrated weight init
    output_calibrated_weight CALC_WEIGHT(clk_100MHz, TARE, CALIBRATE_VAL, RAW_VAL, CALIBRATED_OUTPUT, DP_LOC);

    // 7-segment display driver init
    signed_bcd_driver DISPLAY(clk_100MHz, CALIBRATED_OUTPUT, SEG, AN);

    // Button input for tare and calibration init
    get_tare_and_calibration GET_TARE_CAL(clk_100MHz, tare_button, calib_button,RAW_VAL, DATA_VALID, TARE, CALIBRATE_VAL);

endmodule


module hx711_data_module(  // Handles HX711 input data
    input  wire clk_100MHz,     // Clock input for asynchronous  execution
    input  wire DOUT,           // from HX711 DT pin
    output reg PD_SCK,             // To HX711 SCK pin 
    output wire signed [23:0] RAW_VAL, // 24 bit raw value that gets read out from HX711
    output wire DATA_VALID      // Data flag check
);

    // Timing constant to get 1µs cycle later
    parameter CLKS_PER_HALF_CYCLE = 100;

    // FSM type for state machine
    typedef enum logic [1:0] {
        IDLE         = 2'b00, // State 0: Wait for Dout to go low
        READING_BITS = 2'b01, // State 1: Read the bits from 24 pulses
        NEXT_CONV    = 2'b10, // State 2: The 25th bit to clean things up
        CLEANUP      = 2'b11  // State 3: Run DATA_VALID flag for a cycle to confirm it's valid
    } state_t;

    // Registers
    state_t state;        // The 4 states
    reg [4:0]  bit_index; // Count from 0-24 to cycle the bits (2^5=32)
    reg [23:0] read_val;  // Holds the 24 bits 
    reg [15:0] counter;   // More than large enough for the clock to count to 1 µs

    initial begin // Start everything at 0
        state     = IDLE;
        bit_index = 5'b00000;
        counter   = 16'b0;
        read_val  = 24'b0;
    end

    // State logic
    always_ff @(posedge clk_100MHz) begin // Synchronous logic is used after this point (everything happens at once)
        case(state)
            // This is the default state that happens when no input is detected
            IDLE: begin
                // Default outputs & resets for safety
                bit_index <= 0;
                counter   <= 0;
                // SCK low in idle
                PD_SCK <= 1'b0; // Bring PD_SCK low
                if (DOUT == 1'b0) begin // Start with the data at high so a low means the data is sent 
                    state <= READING_BITS; // DOUT was detected low, so the state is now READING_BITS
                end
                else begin // Otherwise stay in idle
                    state <= IDLE; // DOUT hasn't changed so state is still idle
                end
            end

            // This handles the 24 bits and getting each one recorded
            READING_BITS: begin
                // Count up to 100 to make 1us high or low pulses
                counter <= counter + 1;
                if (PD_SCK == 1'b0) begin
                    // SCK low means drive high after 1us
                    if (counter >= CLKS_PER_HALF_CYCLE) begin // With the clock chosen this is every 1 µs
                        counter <= 0;     // Reset counter to count back up to 100
                        PD_SCK <= 1'b1;   // go high
                    end
                end
                else begin
                    // SCK high → capture data during this phase
                    if (counter == 1) begin
                        // Shift left and bring in newest bit
                        read_val <= {read_val[22:0], DOUT};  // Take the read bit and store in the DOUT
                    end
                    // After 1us high, go low again
                    if (counter >= CLKS_PER_HALF_CYCLE) begin // This 
                        counter <= 0;
                        PD_SCK <= 1'b0;   // go low
                        bit_index <= bit_index + 1; // Next bit brought in

                        if (bit_index == 23) begin
                            // just finished reading 24 bits (0-23)
                            state <= NEXT_CONV;  // A new state for 25th pulse is needed
                        end
                    end
                end
            end


            // This state handles bit 25 to end the 24 inputs
            // Bit 25 has its own state to bypass the record function as it's here only for cleanup
            NEXT_CONV: begin
                // Count up toward 1us like before
                counter <= counter + 1;
                if (PD_SCK == 1'b0) begin
                    // If clock is low, after 1us, raise it
                    if (counter >= CLKS_PER_HALF_CYCLE) begin
                        counter <= 0; // Reset counter for next bit
                        PD_SCK <= 1'b1;    // Rising edge for 25th pulse
                    end
                end
                else begin
                    // SCK is high, so after 1us, drop it again
                    if (counter >= CLKS_PER_HALF_CYCLE) begin
                        counter <= 0;
                        PD_SCK <= 1'b0;    // falling edge finishes 25th pulse
                        // Now totally done with this reading
                        state <= CLEANUP;
                    end
                end

            end

            // This state resets everything to 0 for the next read
            CLEANUP: begin
                // Keep SCK low for safety
                PD_SCK <= 1'b0;
                // Reset counters for next conversion
                counter   <= 0;
                bit_index <= 0;
                state <= IDLE; // Go back to idle
            end
            default: state <= IDLE; // Fallback to idle if no state detected
        endcase
    end


    assign RAW_VAL    = read_val; // RAW_VAL must always be ready to send the weight over to device
    assign DATA_VALID = (state == CLEANUP); // Data is only valid if the cleanuo state has been reached

endmodule



// Set up the  25 bit signed_bcd_driver integer, segments, anodes, and decimal point
module signed_bcd_driver(
                        input CLK,
                        input [24:0] SIGNED_INT_DISPLAY,
                        output reg [7:0]segment,
                        output reg [7:0]anode

    );

    // 100M/100k=1k refreshes per second
    parameter TICKS_PER_DIGIT = 100000;

    // STATIC DECIMAL LOCATION NOW 
    localparam [2:0] DECIMAL_LOCATION = 3;

    // Only 2^17 is barely enough to count up to the value
    reg [16:0] TICK_COUNT = 0; // Timing for multiplex
    reg NEGATIVE = 0; // Number sign storage
    reg [2:0] selected_digit = 0; // Start with the digit at 0
    reg [3:0] active_segment = 0; // Start with segment 0
    reg [27:0]bcd; // full 28-bit BCD representation (7 digits)
    
    integer i; // Use in a loop a bit later
    

    always @(posedge CLK) begin // Update on rising clock edge
        if(TICK_COUNT < TICKS_PER_DIGIT) begin // block the code from continuing briefly
            TICK_COUNT = TICK_COUNT+1;
        end
        else begin
            TICK_COUNT = 0; // Reset tick count for next delay
            selected_digit <= (selected_digit > 7) ? 0 : selected_digit + 1; // Go through each digit
            case(selected_digit) // Find out what digit was used and map to segment
                3'b000: begin
                    active_segment = bcd[3:0];
                    anode = 8'b11111110;
                    
                end
                3'b001: begin
                    active_segment = bcd[7:4];
                    anode = 8'b11111101;
                end
                3'b010: begin
                    active_segment = bcd[11:8];
                    anode = 8'b11111011;
                end
                3'b011: begin
                    active_segment = bcd[15:12];
                    anode = 8'b11110111;
                end
                3'b100: begin
                    active_segment = bcd[19:16];
                    anode = 8'b11101111;
                end
                3'b101: begin
                    active_segment = bcd[23:20];
                    anode = 8'b11011111;
                end
                3'b110: begin
                    active_segment = bcd[27:24];
                    anode = 8'b10111111;
                end
                3'b111: begin
                    active_segment = NEGATIVE?4'b1010:4'b1011;
                    anode = 8'b01111111;
                end
            endcase
        end
    end
    
    // Take the selected segment and light up the needed sections
    always @(posedge CLK) begin
        case(active_segment)
            4'b0000: segment = 8'b00000011; // 0
            4'b0001: segment = 8'b10011111; // 1
            4'b0010: segment = 8'b00100101; // 2
            4'b0011: segment = 8'b00001101; // 3
            4'b0100: segment = 8'b10011001; // 4
            4'b0101: segment = 8'b01001001; // 5
            4'b0110: segment = 8'b01000001; // 6
            4'b0111: segment = 8'b00011111; // 7
            4'b1000: segment = 8'b00000001; // 8
            4'b1001: segment = 8'b00001001; // 9
            4'b1010: segment = 8'b11111101; // negative dash
            default: segment = 8'b11111111; // blank
       endcase 
       // Find the decimal location and turn the decimal portion (segment[0]) off
       // This should always result in digit 3 being followed by a decimal
        if ((selected_digit == DECIMAL_LOCATION) && (selected_digit != 3'b000)) begin;
                if (DECIMAL_LOCATION != 3'b000)
                    segment[0] <= 1'b0;
                else
                    segment[0] <= 1'b1;
                    
        end
end
    
        
    // Fully make sure the binary value corresponds to a decimal
    always @(SIGNED_INT_DISPLAY) begin
        NEGATIVE <= SIGNED_INT_DISPLAY[24];
        bcd=0;		 	
        for (i=0;i<24;i=i+1) begin					              //Iterate once for each bit in input number
           if (bcd[3:0] >= 5) bcd[3:0] = bcd[3:0] + 3;		        //If any BCD digit is >= 5, add three
           if (bcd[7:4] >= 5) bcd[7:4] = bcd[7:4] + 3;
           if (bcd[11:8] >= 5) bcd[11:8] = bcd[11:8] + 3;
           if (bcd[15:12] >= 5) bcd[15:12] = bcd[15:12] + 3;
           if (bcd[19:16] >= 5) bcd[19:16] = bcd[19:16] + 3;
           if (bcd[23:20] >= 5) bcd[23:20] = bcd[23:20] + 3;
           if (bcd[27:24] >= 5) bcd[27:24] = bcd[27:24] + 3;
           bcd = {bcd[26:0],SIGNED_INT_DISPLAY[23-i]};	//Shift one bit, and shift in proper bit from input 
        end
    end 
endmodule

// This module applies to the "generate calibrated value" module
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


// Get TARE and CALIBRATE_VAL based on button presses and RAW_VAL
// These are the center and right switches for tare and calibration respectively
module get_tare_and_calibration(
    input  wire        clk_100MHz,       // main system clock
    input  wire        tare_button,      // raw noisy button
    input  wire        calib_button,     // raw noisy button
    input  wire        DATA_VALID,       // high only when RAW_VAL is good (See HX711 for how it's found)
    input  wire signed [23:0] RAW_VAL,   // current HX711 reading (See HX711 for how it's found)

    output reg  signed [23:0] TARE,
    output reg  signed [23:0] CALIBRATE_VAL
);

    // Internal wires for button pulses
    wire tare_pulse;
    wire calib_pulse;

    // Slow clock for debouncing 
    reg [26:0] counter = 0;
    reg slow_clk = 0;

    // Slow debounce clock setup (very similar to lab 4)
    // 2.5 ms clock period (or 4Hz frequency)
    always @(posedge clk_100MHz) begin
        counter   <= (counter >= 249999) ? 0 : counter + 1; // Once counter reaches 250k, reset it to 0
        slow_clk  <= (counter < 125000) ? 1'b0 : 1'b1;      // Keep slow_clk low then high for each counter half
    end

    // For TARE button
    wire t_q0, t_q1, t_q2, t_q2_bar; // The intermediate wire to use in debouce (similar to lab 4)
    reg t_dff0, t_dff1, t_dff2; // t_dff0 is the input, t_dff1 gives time to sync, and t_dff2 is output 

    always @(posedge slow_clk) t_dff0 <= tare_button; // t_dff0 is the raw press
    always @(posedge slow_clk) t_dff1 <= t_dff0; // 2.5 ms for debounce used to filter out noise
    always @(posedge slow_clk) t_dff2 <= t_dff1; // Debounced button that now waits for rising edge

    assign t_q1     = t_dff1; // Store  current debounced  value
    assign t_q2     = t_dff2; // Store previous debounce value
    assign t_q2_bar = ~t_q2; // Use this value in  tare_pulse
    assign tare_pulse = t_q1 & t_q2_bar; // tare_pulse true only when the button wasn't pressed but is now (rising edge)


    // For CALIB button (Near indentical to Tare's debounce code)
    wire c_q1, c_q2, c_q2_bar; // The intermediate wire to use in debouce (similar to lab 4)
    reg c_dff0, c_dff1, c_dff2; // t_dff0 is the input, t_dff1 gives time to sync, and t_dff2 is output

    always @(posedge slow_clk) c_dff0 <= calib_button; // c_dff0 is the raw press
    always @(posedge slow_clk) c_dff1 <= c_dff0; // 2.5 ms for debounce used to filter out noise
    always @(posedge slow_clk) c_dff2 <= c_dff1; // Debounced button that now waits for rising edge

    assign c_q1      = c_dff1; // Store  current debounced  value
    assign c_q2      = c_dff2; // Store previous debounce value
    assign c_q2_bar  = ~c_q2;  // Use this value in  tare_pulse
    assign calib_pulse = c_q1 & c_q2_bar; // tare_pulse true only when the button wasn't pressed but is now (rising edge)

    // Initialize values at the start
    initial begin
        TARE          = 24'sd0;
        CALIBRATE_VAL = 24'sd100000;   // Default until user presses CALIB button
    end

    // Store TARE only on valid button press
    always @(posedge tare_pulse) begin
        if (DATA_VALID)
            TARE <= RAW_VAL;
    end


    // Store CALIBRATE_VAL on button press
    always @(posedge calib_pulse) begin
        if (DATA_VALID)
            CALIBRATE_VAL <= RAW_VAL;
    end

endmodule


