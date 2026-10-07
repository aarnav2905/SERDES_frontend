`timescale 1ns/1ps
module enc8b10b(input  wire       clk,
    input  wire       rst_n,
 
 
    input  wire [7:0] data_in,      // 8-bit input byte
    input  wire        k_in,        // 1 = data_in is a control/K character
    input  wire        valid_in,    // upstream has data ready
 
    output reg  [9:0] data_out,     // 10-bit encoded symbol
    output reg          valid_out,   // encoded symbol is valid this cycle
    output reg          rd_error     // flags illegal encode attempt (e.g. invalid K char)
);
 
    // ---- Internal state ----
    reg running_disparity;   // 0 = RD-, 1 = RD+
 
 
    reg [5:0] enc_5b6b_table [0:31];   // c_enc_5b6b_table equivalent
    reg       disPar_6b_table [0:31];  // c_disPar_6b equivalent
    reg [3:0] enc_3b4b_table [0:7];    // c_enc_3b_4b_table equivalent
    reg       disPar_4b_table [0:7];   // c_disPar_4b equivalent
    reg [5:0] k_enc_6b [0:0];   // just K28.5's RD- value
    reg [3:0] k_enc_4b [0:0];
 
    initial begin
 
    enc_5b6b_table[0]  = 6'b100111; // D00
    enc_5b6b_table[1]  = 6'b011101; // D01
    enc_5b6b_table[2]  = 6'b101101; // D02
    enc_5b6b_table[3]  = 6'b110001; // D03
    enc_5b6b_table[4]  = 6'b110101; // D04
    enc_5b6b_table[5]  = 6'b101001; // D05
    enc_5b6b_table[6]  = 6'b011001; // D06
    enc_5b6b_table[7]  = 6'b111000; // D07
    enc_5b6b_table[8]  = 6'b111001; // D08
    enc_5b6b_table[9]  = 6'b100101; // D09
    enc_5b6b_table[10] = 6'b010101; // D10
    enc_5b6b_table[11] = 6'b110100; // D11
    enc_5b6b_table[12] = 6'b001101; // D12
    enc_5b6b_table[13] = 6'b101100; // D13
    enc_5b6b_table[14] = 6'b011100; // D14
    enc_5b6b_table[15] = 6'b010111; // D15
    enc_5b6b_table[16] = 6'b011011; // D16
    enc_5b6b_table[17] = 6'b100011; // D17
    enc_5b6b_table[18] = 6'b010011; // D18
    enc_5b6b_table[19] = 6'b110010; // D19
    enc_5b6b_table[20] = 6'b001011; // D20
    enc_5b6b_table[21] = 6'b101010; // D21
    enc_5b6b_table[22] = 6'b011010; // D22
    enc_5b6b_table[23] = 6'b111010; // D23
    enc_5b6b_table[24] = 6'b110011; // D24
    enc_5b6b_table[25] = 6'b100110; // D25
    enc_5b6b_table[26] = 6'b010110; // D26
    enc_5b6b_table[27] = 6'b110110; // D27
    enc_5b6b_table[28] = 6'b001110; // D28
    enc_5b6b_table[29] = 6'b101110; // D29
    enc_5b6b_table[30] = 6'b011110; // D30
    enc_5b6b_table[31] = 6'b101011; // D31
 
    end
 
initial begin
    disPar_6b_table[0]  = 1'b1;
    disPar_6b_table[1]  = 1'b1;
    disPar_6b_table[2]  = 1'b1;
    disPar_6b_table[3]  = 1'b0;
    disPar_6b_table[4]  = 1'b1;
    disPar_6b_table[5]  = 1'b0;
    disPar_6b_table[6]  = 1'b0;
    disPar_6b_table[7]  = 1'b0;
    disPar_6b_table[8]  = 1'b1;
    disPar_6b_table[9]  = 1'b0;
    disPar_6b_table[10] = 1'b0;
    disPar_6b_table[11] = 1'b0;
    disPar_6b_table[12] = 1'b0;
    disPar_6b_table[13] = 1'b0;
    disPar_6b_table[14] = 1'b0;
    disPar_6b_table[15] = 1'b1;
    disPar_6b_table[16] = 1'b1;
    disPar_6b_table[17] = 1'b0;
    disPar_6b_table[18] = 1'b0;
    disPar_6b_table[19] = 1'b0;
    disPar_6b_table[20] = 1'b0;
    disPar_6b_table[21] = 1'b0;
    disPar_6b_table[22] = 1'b0;
    disPar_6b_table[23] = 1'b1;
    disPar_6b_table[24] = 1'b1;
    disPar_6b_table[25] = 1'b0;
    disPar_6b_table[26] = 1'b0;
    disPar_6b_table[27] = 1'b1;
    disPar_6b_table[28] = 1'b0;
    disPar_6b_table[29] = 1'b1;
    disPar_6b_table[30] = 1'b1;
    disPar_6b_table[31] = 1'b1;
end
 
initial begin
    enc_3b4b_table[0] = 4'b1011; // Dx0
    enc_3b4b_table[1] = 4'b1001; // Dx1
    enc_3b4b_table[2] = 4'b0101; // Dx2
    enc_3b4b_table[3] = 4'b1100; // Dx3
    enc_3b4b_table[4] = 4'b1101; // Dx4
    enc_3b4b_table[5] = 4'b1010; // Dx5
    enc_3b4b_table[6] = 4'b0110; // Dx6
    enc_3b4b_table[7] = 4'b1110; // DxP7
end
 
initial begin
    disPar_4b_table[0] = 1'b1;
    disPar_4b_table[1] = 1'b0;
    disPar_4b_table[2] = 1'b0;
    disPar_4b_table[3] = 1'b0;
    disPar_4b_table[4] = 1'b1;
    disPar_4b_table[5] = 1'b0;
    disPar_4b_table[6] = 1'b0;
    disPar_4b_table[7] = 1'b1;
end
initial begin
    k_enc_6b[0] = 6'b001111;
    k_enc_4b[0] = 4'b1010;
end
 
 
// ---- Step 1: raw lookups (combinational, with K-character override) ----
wire is_k28_5 = k_in && (data_in == 8'b101_11100);
 
wire [5:0] enc_5b6b      = is_k28_5 ? k_enc_6b[0] : enc_5b6b_table[data_in[4:0]];
wire        disp_5b6b     = is_k28_5 ? 1'b1        : disPar_6b_table[data_in[4:0]];
wire [5:0] enc_5b6b_alt  = ~enc_5b6b;
 
wire [3:0] enc_3b4b      = is_k28_5 ? k_enc_4b[0] : enc_3b4b_table[data_in[7:5]];
wire        disp_3b4b     = is_k28_5 ? 1'b1        : disPar_4b_table[data_in[7:5]];
wire [3:0] enc_3b4b_alt  = ~enc_3b4b;
 
// ---- Step 2: sequential disparity decision chain (combinational) ----
reg [5:0] chosen_5b6b;
reg [3:0] chosen_3b4b;
reg       intermediate_rd;
reg       final_rd;
 
 
    always @(*) begin
        if (is_k28_5) begin
            // K28.5 is an atomic RD-/RD+ pair: pick the WHOLE 10-bit codeword
            // based on the running disparity coming into this byte. No
            // intermediate chaining between the two halves, unlike regular
            // D-characters.
            if (running_disparity == 1'b0) begin   // RD- : use default halves
                chosen_5b6b = enc_5b6b;
                chosen_3b4b = enc_3b4b;
                final_rd    = 1'b1;
            end else begin                          // RD+ : use complemented halves
                chosen_5b6b = enc_5b6b_alt;
                chosen_3b4b = enc_3b4b_alt;
                final_rd    = 1'b0;
            end
            intermediate_rd = final_rd; // unused in this branch, kept defined
        end else begin
            // Decide 5B/6B first, using current running_disparity
            if (!disp_5b6b) begin
                chosen_5b6b     = enc_5b6b;
                intermediate_rd = running_disparity;
            end else begin
                if (running_disparity == 1'b0) begin        // RD negative -> add +2
                    chosen_5b6b     = enc_5b6b;
                    intermediate_rd = 1'b1;
                end else begin                                // RD positive -> use -2 complement
                    chosen_5b6b     = enc_5b6b_alt;
                    intermediate_rd = 1'b0;
                end
            end
 
            // Decide 3B/4B next, using intermediate_rd (NOT running_disparity)
            if (!disp_3b4b) begin
                chosen_3b4b = enc_3b4b;
                final_rd    = intermediate_rd;
            end else begin
                if (intermediate_rd == 1'b0) begin
                    chosen_3b4b = enc_3b4b;
                    final_rd    = 1'b1;
                end else begin
                    chosen_3b4b = enc_3b4b_alt;
                    final_rd    = 1'b0;
                end
            end
        end
    end
 
// NOTE: DxP7/alt7 comma-collision-avoidance logic for D.x.7 data characters
//       is intentionally not implemented in this project's scope.
 
    // ---- Step 3: register outputs and update running disparity ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running_disparity <= 1'b0;
            data_out           <= 10'b0;
            valid_out          <= 1'b0;
            rd_error           <= 1'b0; 
        end else if (valid_in) begin
            running_disparity <= final_rd;
            data_out           <= {chosen_5b6b, chosen_3b4b};
            valid_out          <= 1'b1;
            rd_error           <= k_in && !is_k28_5;
        end else begin
            valid_out <= 1'b0;
            rd_error  <= 1'b0; 
        end
    end
 
endmodule
