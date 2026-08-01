module fnv1a_core (
	input 				clk,
	input 				reset_n,
	input 				start,
	input		  [31:0]	target,
	output reg			done,
	output reg	   	found,
	output reg [31:0] match_idx
);

localparam 		 CHAR_LO = 8'h61;
localparam 		 CHAR_HI = 8'h7A;
localparam 		 CHARSET_N = 26;
localparam 		 PW_LEN = 4;
localparam [31:0] FNV_OFFSET = 32'h811c9dc5;
localparam [31:0] FNV_PRIME = 32'h01000193;
localparam [31:0] MAX = 26*26*26*26;

reg [31:0 ] idx;
reg 			running;




wire [7:0] b0 = CHAR_LO + (idx	% CHARSET_N);
wire [7:0] b1 = CHAR_LO + ((idx/26) % CHARSET_N);
wire [7:0] b2 = CHAR_LO + ((idx/676) % CHARSET_N);
wire [7:0] b3 = CHAR_LO + ((idx/17576) % CHARSET_N);

wire [31:0] h0 = (FNV_OFFSET ^ b0) * FNV_PRIME;
wire [31:0] h1 = (h0 ^ b1) * FNV_PRIME;
wire [31:0] h2 = (h1 ^ b2)  * FNV_PRIME;
wire [31:0] h3 = (h2 ^ b3) * FNV_PRIME;


always @(posedge clk or negedge reset_n) begin
	if (!reset_n) begin
		idx <= 0;
		match_idx <= 0;
		running <= 0;
		done <= 0;
		found <= 0;
	end else if (start && !running) begin
		idx <= 0;
		running <= 1;
		done <= 0;
		found <= 0;
	end else if (running) begin
		if (h3 == target) begin
			found <= 1;
			match_idx <= idx;
			done <= 1;
			running <= 0;
		end else if (idx == MAX -1 ) begin
			running <= 0; done <= 1;
		end else begin
			idx <= idx + 1;
		end
	end
end
	
	

endmodule