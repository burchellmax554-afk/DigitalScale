module hx711_data_module(  // Handles HX711 input data over a FSM 
    input  wire clk_100MHz,     // Clock input for synchronous  execution
    input  wire DOUT,           // From HX711 DT pin
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
                        PD_SCK <= 1'b1;   // Go high
                    end
                end
                else begin
                    // SCK high means capture data during this phase
                    if (counter == 1) begin
                        // Shift left and bring in newest bit
                        read_val <= {read_val[22:0], DOUT};  // Take the read bit and store in the DOUT
                    end
                    // After 1us high, go low again
                    if (counter >= CLKS_PER_HALF_CYCLE) begin 
                        counter <= 0;
                        PD_SCK <= 1'b0;   // Go low
                        bit_index <= bit_index + 1; // Next bit brought in

                        if (bit_index == 23) begin
                            // Just finished reading 24 bits (0-23)
                            state <= NEXT_CONV;  // A new state for 25th pulse is needed
                        end
                    end
                end
            end


            // This state handles bit 25 to end the 24 inputs
            // Bit 25 has its own state to bypass the record function as it's here only for cleanup and skips recording
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
                        PD_SCK <= 1'b0;    // Falling edge finishes 25th pulse
                        // Now totally done with this reading
                        state <= CLEANUP; // Move on to CLEANUP
                    end
                end

            end

            // This state resets everything to 0 for the next read
            CLEANUP: begin
                PD_SCK <= 1'b0; // Keep SCK low for safety
                // Reset counters for next conversion
                counter   <= 0;
                bit_index <= 0;
                state <= IDLE; // Go back to idle
            end
            default: state <= IDLE; // Fallback to idle if no state detected (failsafe)
        endcase
    end

    assign RAW_VAL    = read_val; // RAW_VAL must always be ready to send the weight over to device
    assign DATA_VALID = (state == CLEANUP); // Data is only valid if the cleanup state has been reached

endmodule