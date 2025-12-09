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
    
    integer i; // Use in a loop for bit shifts
    

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
       // Find the decimal location and turn the decimal portion (segment[0]) on (set to 0)
       // This always results in digit 3 being followed by a decimal
        if ((selected_digit == DECIMAL_LOCATION) && (selected_digit != 3'b000)) begin;
                if (DECIMAL_LOCATION != 3'b000)
                    segment[0] <= 1'b0; // Decimal point set to 0 (on)
                else
                    segment[0] <= 1'b1; // Decimal point set to 1 (off)
                    
        end
end
        
    // Fully make sure the binary value corresponds to a decimal
    always @(SIGNED_INT_DISPLAY) begin
        NEGATIVE <= SIGNED_INT_DISPLAY[24];
        bcd=0;		 	
        for (i=0;i<24;i=i+1) begin					                // Iterate once for each bit in input number
           if (bcd[3:0] >= 5) bcd[3:0] = bcd[3:0] + 3;		        // If any BCD digit is >= 5, add three
           if (bcd[7:4] >= 5) bcd[7:4] = bcd[7:4] + 3;              // This is a necessary step to convert to decimal
           if (bcd[11:8] >= 5) bcd[11:8] = bcd[11:8] + 3;
           if (bcd[15:12] >= 5) bcd[15:12] = bcd[15:12] + 3;
           if (bcd[19:16] >= 5) bcd[19:16] = bcd[19:16] + 3;
           if (bcd[23:20] >= 5) bcd[23:20] = bcd[23:20] + 3;
           if (bcd[27:24] >= 5) bcd[27:24] = bcd[27:24] + 3;
           bcd = {bcd[26:0],SIGNED_INT_DISPLAY[23-i]};	// Shift one bit, and shift in proper bit from input 
        end
    end 
endmodule