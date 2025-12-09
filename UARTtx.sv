// This module handles data being sent to the device.
// It's mostly here as a bonus, proof-of-concept implementation where in theory, a
// terminal, MCU, or oscilloscope takes in the weight data to digitally store and output it.
// Presently, plugging in an oscilloscope does indeed show a signal being processed
module UARTtx(
    input wire clk_100MHz,     // Clock input for asynchronous  execution
    input wire signed [24:0] WEIGHTED,  // 25-bit input (weight)
    output reg tx // Output to use for a terminal usb
);

    reg baud_tick; // Pulses high once per baud period 

    // FSM for bit-level logic
    typedef enum logic [1:0] {
	   IDLE_BIT	    = 2'b00, // When no data is sent
	   START_BIT    = 2'b01, // The start of the data being sent
	   DATA_BIT	    = 2'b10, // The data is sent here
	   STOP_BIT	    = 2'b11  // This final bit signals the stream is over
       } bit_state_t;

       bit_state_t state_bit = IDLE_BIT; // Start in idle
	
    // FSM for byte-level logic
    typedef enum logic [3:0] {
        IDLE_BYTE    = 4'b0000, // No transmission in progress, wait for bit FSM to be idle
        SEND0        = 4'b0001, // Load and transmit byte 0
        WAIT0_DONE   = 4'b0010, // Wait for completion of byte 0
	    SEND1	     = 4'b0011, // Load and transmit byte 1
	    WAIT1_DONE   = 4'b0100, // Wait for completion of byte 1
	    SEND2        = 4'b0101, // Load and transmit byte 2
	    WAIT2_DONE   = 4'b0110, // Wait for completion of byte 2
	    SEND3        = 4'b0111, // Load and transmit byte 3
	    WAIT3_DONE   = 4'b1000  // Wait for completion of byte 3
	    } byte_state_t;
	    
	    byte_state_t state_byte = IDLE_BYTE; // Start in idle state

    parameter int DIV = 10417; // Choose DIV = 100MHz / 9600 (BAUD rate) = 10417, means period for one bit is ~104us
    reg [13:0] cnt = 14'b0;	// 2^14-1 = 16383, the lowest value to hold 10417
    reg [2:0] bit_index = 3'b0; // Index for 8 bits
    reg [24:0] latched_weight = 25'b0; // Reserved for future use (unused in current version)
    
    // Split the 25 bits into 4 bytes 
    wire [7:0] byte0 = latched_weight[7:0]; // Bits 0-7 stored here
    wire [7:0] byte1 = latched_weight[15:8]; // Bits 8-15 stored here
    wire [7:0] byte2 = latched_weight[23:16]; // Bits 16-23 stored here
    wire [7:0] byte3 = {7'b0, latched_weight[24]}; // Bit 24 stored here 

    reg [7:0] load_byte = 8'b0; // Initialize current byte to 0 before data is loaded
    
    // Activate tx flag once at the start to be ready to send the data
    initial begin 
        tx = 1'b1; 
    end
    
    always_ff @(posedge clk_100MHz) begin // Synchronous logic needed after this point
	// Baud tick generator
        if (cnt == DIV-1) begin 
            cnt <= 0; // Reset counter as bit was transmitted by this point
            baud_tick <= 1; // This flags UART to send the next bit
        end
        else begin
	        cnt <= cnt + 1; // Count up to clk division value (10417)
	        baud_tick <= 0; // Ensure the flag to send the next bit is off until the previous bit is done
        end
	
	   // FSMs to send data as bytes
	    if (baud_tick) begin // If a new bit is ready to be sent
	    // bit FSM (outputs one new bit per baud period)
	        case (state_bit) // Bit-level FSM controls start, data, and stop bits
	            IDLE_BIT: begin // If the bit is idle, continue waiting fot he start bit
	                tx <= 1; // Idle line = 1
		        end		

		        START_BIT: begin // If he bit is start, begin the transmission
                    tx <= 0; // This triggers the start bit to begin transmitting
		            state_bit <= DATA_BIT; // Go to the DATA_BIT state to transmit
		            bit_index <= 0; // Go to bit 0 of the current byte
		        end

		        DATA_BIT: begin // Output each data bit, one per baud tick
		            tx <= load_byte[bit_index]; // Load the bits into the byte
		            if (bit_index == 7) // Once the last bit is sent
			            state_bit <= STOP_BIT; // Go to the stop bit now that the byte is complere
		            else
			            bit_index <= bit_index + 1; // Cycle through the 8 bits across the byte
		        end

		        STOP_BIT: begin // If the bit is stop, stop the transmission, the byte has ended
		            tx <= 1; // This triggers the stop bit to stop transmitting
		            state_bit <= IDLE_BIT; // Go back to idle for the next byte
		        end
	        endcase

            // Byte FSM (changes state when bit FSM finishes sending a byte)
	        case (state_byte)
		        IDLE_BYTE: begin // No transmission in progress, wait for IDLE BIT
		            if (state_bit == IDLE_BIT)  // Bit FSM being idle too means a new a byte is ready
			            state_byte <= SEND0; // Start sending the first byte
		            else
			            state_byte <= IDLE_BYTE; // Otherwise keep waitng for input
			            latched_weight <= WEIGHTED; // Capture newest weight every cycle
		        end       

		        SEND0: begin // Loads and transmits byte 0 over UART
		            if (state_bit == IDLE_BIT) begin // Bit FSM being idle too means a new a byte is ready
		                load_byte <= byte0; // Load up byte 0 to start transmission
		                state_bit <= START_BIT; // Start the 8 bit transmission
		                state_byte <= WAIT0_DONE; // Wait for the transmission to finish 
		            end
		        end

		        WAIT0_DONE: begin // Wait for completion of byte 0
                    if (state_bit == IDLE_BIT) // Bit FSM being idle too means a new a byte is ready
			            state_byte <= SEND1; // Move onto byte 1 after byte 0 is done
		        end
		
		        SEND1: begin // Loads and transmits byte 1 over UART
		            if (state_bit == IDLE_BIT) begin // Bit FSM being idle too means a new a byte is ready
		                load_byte <= byte1; // Load up byte 1 to start transmission
		                state_bit <= START_BIT; // Start the 8 bit transmission
		                state_byte <= WAIT1_DONE; // Wait for the transmission to finish 
		            end
		        end

		        WAIT1_DONE: begin // Wait for completion of byte 1
		            if (state_bit == IDLE_BIT) // Bit FSM being idle too means a new a byte is ready
			            state_byte <= SEND2; // Move onto byte 2 after byte 1 is done
		        end

		        SEND2: begin // Loads and transmits byte 2 over UART
		            if (state_bit == IDLE_BIT) begin // Bit FSM being idle too means a new a byte is ready
		                load_byte <= byte2; // Load up byte 2 to start transmission
		                state_bit <= START_BIT; // Start the 8 bit transmission
		                state_byte <= WAIT2_DONE; // Wait for the transmission to finish 
		            end
		        end

		        WAIT2_DONE: begin // Wait for completion of byte 2
		            if (state_bit == IDLE_BIT) // Bit FSM being idle too means a new a byte is ready
			            state_byte <= SEND3; // Move onto byte 3 after byte 2 is done
		            end

	            SEND3: begin // Loads and transmits byte 3 over UART
		            if (state_bit == IDLE_BIT) begin // Bit FSM being idle too means a new a byte is ready
		                load_byte <= byte3; // Load up byte 3 to start transmission
		                state_bit <= START_BIT; // Start the 8 bit transmission
		                state_byte <= WAIT3_DONE; // Wait for the transmission to finish 
		            end
		        end

		        WAIT3_DONE: begin // Wait for completion of byte 3
		            if (state_bit == IDLE_BIT) // Bit FSM being idle too means all bytes are now done
			            state_byte <= IDLE_BYTE; // Go back to idle after byte 3 is done
		        end
		    endcase
        end
    end

endmodule