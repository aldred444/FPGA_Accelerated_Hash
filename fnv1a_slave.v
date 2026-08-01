module fnv1a_slave (

	input clk,
	input reset_n,
	
	// Avalon MM-Slave
	input [2:0] address,
	input read,
	input write,
	input  [31:0] writeData,
	output reg [31:0] readData
);

    // register map (word addresses):
    //  0 : TARGET  (write) - hash to crack
    //  1 : CONTROL (write) - bit0 = start pulse
    //  2 : STATUS  (read)  - bit0=done, bit1=found
    //  3 : RESULT  (read)  - match_idx
	 
	 reg run_start;
	 wire run_done, pw_found;
	 reg [31:0] target_hash;
	 wire [31:0] match_idx;
	 
	 
	 always @(posedge clk or negedge reset_n) begin
		if (!reset_n) begin
			target_hash <= 0;
			run_start   <= 0;
		end else begin
			run_start  <= 0;
			if (write) begin
				case (address)
					3'd0: target_hash <= writeData;
					3'd1: run_start <= writeData[0];
				endcase
			end
		end	
	end
	
	 always @(*) begin
		case (address)
			3'd2: readData  = {30'b0, pw_found, run_done};
			3'd3: readData  = match_idx;
			default: readData = 32'b0;
		endcase
	 end
	 
	 fnv1a_core pwd_cracker (
	.clk(clk),
	.reset_n(reset_n),
	.start(run_start),
	.target(target_hash),
	.done(run_done),
	.found(pw_found),
	.match_idx(match_idx)
);

endmodule
