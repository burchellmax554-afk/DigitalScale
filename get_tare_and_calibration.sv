module get_tare_and_calibration( // This module handles tare and calib input, debouncing and synching both inputs 
    input  wire        clk_100MHz,     // Main system clock
    input  wire        tare_button,    // Raw noisy button
    input  wire        calib_button,   // Raw noisy button
    input  wire        DATA_VALID,     // high once per HX711 conversion
    input  wire signed [23:0] RAW_VAL, // raw reading from HX711
    output reg  signed [23:0] TARE,          // stored tare
    output reg  signed [23:0] CALIBRATE_VAL  // stored calibration constant
);

    // Slow clock for debouncing (about 200 Hz)
    // This will need to be synched up later 
    reg [26:0] counter = 0;
    reg        slow_clk = 0;
    always @(posedge clk_100MHz) begin
        if (counter >= 27'd249_999) begin // Toggle slow clock
            counter  <= 0;  // Reset counter back to 0
            slow_clk <= ~slow_clk;   // Toggle every 2.5 ms (halfway through the 5ms period)
        end else begin 
            counter <= counter + 1; // Count up to toggle value
        end
    end

    // TARE debounce (in slow clock domain)
    // Set up a rising edge detection
    reg t_dff0 = 0, t_dff1 = 0, t_dff2 = 0;
    always @(posedge slow_clk) begin
        t_dff0 <= tare_button;
        t_dff1 <= t_dff0;
        t_dff2 <= t_dff1;
    end
    wire tare_pulse_slow = t_dff1 & ~t_dff2; // Rising edge detection

    // CALIB debounce (in slow clock domain)
    // Set up a rising edge detection
    reg c_dff0 = 0, c_dff1 = 0, c_dff2 = 0;
    always @(posedge slow_clk) begin
        c_dff0 <= calib_button;
        c_dff1 <= c_dff0;
        c_dff2 <= c_dff1;
    end
    wire calib_pulse_slow = c_dff1 & ~c_dff2; // Rising edge detection

    // Synchronize 200Hz pulses into 100 MHz domain 
    // Basically no pulses will detected without this because DATA_VALID won't line up
    reg t_sync0 = 0, t_sync1 = 0; // Initialize tare synch pulse to 0
    reg c_sync0 = 0, c_sync1 = 0; // Initialize calibration synch pulses to 0
    always @(posedge clk_100MHz) begin // Synchronous logic required
        t_sync0 <= tare_pulse_slow; // Set the initial tare pulse the same value as the 200Hz rising edge
        t_sync1 <= t_sync0; // 1µs cycle later for the new tare state
        c_sync0 <= calib_pulse_slow; // Set the initial calib pulse the same value as the 200Hz rising edge
        c_sync1 <= c_sync0; // 1µs cycle later for the new tare state
    end
    wire tare_pulse  = t_sync0 & ~t_sync1; // New 100MHz rising edge detection now set up for tare
    wire calib_pulse = c_sync0 & ~c_sync1; // New 100MHz rising edge detection now set up for calibration

    // Track newest RAW_VAL only when valid and synched
    reg signed [23:0] last_raw_val = 24'sd0;
    always @(posedge clk_100MHz) begin // Sequential logic after this point
        if (DATA_VALID) begin
            last_raw_val <= RAW_VAL; // Store newest clean sample
        end
    end

    // Initialize stored values
    initial begin
        TARE          = 24'sd0; // Tare stays at 0
        CALIBRATE_VAL = 24'sd100000; // Safe starting calibration
    end

    // Latch TARE and CALIBRATE_VAL on button press
    always @(posedge clk_100MHz) begin
        // Store new tare value 
        if (tare_pulse) begin // If a debounced tare press was detected
            TARE <= last_raw_val; // Reset the scale value to tare value
        end
        if (calib_pulse) begin // If a debouced calibration press was detected
            if ((last_raw_val - TARE) != 24'sd0) // Failsafe to stop division by 0
                CALIBRATE_VAL <= last_raw_val - TARE; // Subtract from tare to find true weight after calibration
        end
        
    end

endmodule