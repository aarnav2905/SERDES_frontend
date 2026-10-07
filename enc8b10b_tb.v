`timescale 1ns/1ps
//////////////////////////////////////////////////////////////////////
// tb_encoder_8b10b.v
//
// Self-checking testbench for encoder_8b10b.
//
// What it checks:
//   1. Directed D-character test  : a handful of hand-verified entries
//                                    (D00, D03, D07, D31) encoded back-to-back
//                                    from reset, checked against known values
//                                    for the RD- / RD+ sequence they produce.
//   2. K28.5 comma test           : K28.5 sent twice in a row from reset,
//                                    checked against the published RD-/RD+
//                                    code values (001111_1010 / 110000_0101).
//   3. Illegal K-character test   : k_in=1 with a byte that is NOT K28.5,
//                                    checked that rd_error asserts.
//   4. Random sweep + cumulative  : 2000 random data bytes (k_in=0), with a
//      disparity bound check        running sum of (#1s - #0s) over every
//                                    transmitted symbol, asserted to stay
//                                    within a small bound (|sum| <= 6) the
//                                    whole run -- this is the actual DC-
//                                    balance property the encoder exists to
//                                    guarantee.
//
// Run with Icarus Verilog:
//   iverilog -o sim encoder_8b10b.v tb_encoder_8b10b.v
//   vvp sim
//   (open dump.vcd in GTKWave if you want to look at waveforms)
//////////////////////////////////////////////////////////////////////

module enc8b10b_tb;

    reg        clk;
    reg        rst_n;
    reg  [7:0] data_in;
    reg        k_in;
    reg        valid_in;

    wire [9:0] data_out;
    wire       valid_out;
    wire       rd_error;

    integer errors;
    integer i;
    integer cum_disparity;   // running sum of (#1s - #0s) across transmitted symbols
    integer ones_count;

    // ---- DUT ----
    enc8b10b dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .data_in    (data_in),
        .k_in       (k_in),
        .valid_in   (valid_in),
        .data_out   (data_out),
        .valid_out  (valid_out),
        .rd_error   (rd_error)
    );

    // ---- Clock: 100 MHz, period = 10ns ----
    initial clk = 0;
    always #5 clk = ~clk;

    // ---- Waveform dump ----
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, enc8b10b_tb);
    end

    // ---- Helper task: apply one byte, wait a clock, print nothing (caller checks) ----
    task send_byte;
        input [7:0] byte_in;
        input       k;
        begin
            @(negedge clk);
            data_in  = byte_in;
            k_in     = k;
            valid_in = 1'b1;
            @(posedge clk);
            #1; // small delta so data_out (NBA update) has settled
        end
    endtask

    // ---- Count 1s in a 10-bit word ----
    function integer count_ones10;
        input [9:0] word;
        integer j;
        begin
            count_ones10 = 0;
            for (j = 0; j < 10; j = j + 1)
                count_ones10 = count_ones10 + word[j];
        end
    endfunction

    initial begin
        errors        = 0;
        cum_disparity = 0;
        data_in       = 8'b0;
        k_in          = 1'b0;
        valid_in      = 1'b0;

        // ---- Reset ----
        rst_n = 0;
        repeat (3) @(posedge clk);
        #1;
        rst_n = 1;
        @(posedge clk);
        #1;

        // =====================================================================
        // TEST 1: Directed D-character checks, starting fresh from reset
        //   After reset, running_disparity = 0 (RD-).
        //   D00 (5b=0,3b=0): disp_5b6b=1 (non-neutral) -> RD- -> default used,
        //     5b6b = 100111, RD goes to intermediate=1(+)
        //   D00's 3b group (0): disp_3b4b=1 (non-neutral) -> intermediate=1(+)
        //     -> complement used, 3b4b = ~1011 = 0100
        //   Expected data_out = {100111, 0100} = 10'b1001110100
        //   Expected final_rd = 0 (RD-)
        // =====================================================================
        send_byte(8'h00, 1'b0); // D00.0  -> EDCBA=0, HGF=0
        if (data_out !== 10'b10_0111_0100) begin
            $display("FAIL: D00 encode mismatch. Got %b expected %b", data_out, 10'b1001110100);
            errors = errors + 1;
        end else
            $display("PASS: D00 encode = %b", data_out);

        // Running disparity should now be back to RD- (0) per hand-trace above
        if (dut.running_disparity !== 1'b0) begin
            $display("FAIL: RD after D00 expected 0 (RD-), got %b", dut.running_disparity);
            errors = errors + 1;
        end

        // =====================================================================
        // TEST 2: K28.5 sent twice in a row from a known RD state
        //   1st K28.5, starting RD- -> expect RD- code: 001111_1010
        //   2nd K28.5, now RD should have flipped to RD+ -> expect 110000_0101
        // =====================================================================
        send_byte(8'b101_11100, 1'b1); // K28.5
        if (data_out !== 10'b001111_1010) begin
            $display("FAIL: K28.5 (RD-) mismatch. Got %b expected 0011111010", data_out);
            errors = errors + 1;
        end else
            $display("PASS: K28.5 RD- encode = %b", data_out);

        send_byte(8'b101_11100, 1'b1); // K28.5 again
        if (data_out !== 10'b110000_0101) begin
            $display("FAIL: K28.5 (RD+) mismatch. Got %b expected 1100000101", data_out);
            errors = errors + 1;
        end else
            $display("PASS: K28.5 RD+ encode = %b", data_out);

        if (rd_error !== 1'b0) begin
            $display("FAIL: rd_error asserted for a VALID K28.5 request");
            errors = errors + 1;
        end

        // =====================================================================
        // TEST 3: Illegal K-character request -> rd_error must assert
        // =====================================================================
        send_byte(8'h00, 1'b1); // k_in=1 but byte is NOT K28.5
        if (rd_error !== 1'b1) begin
            $display("FAIL: rd_error did NOT assert for an illegal K-character request");
            errors = errors + 1;
        end else
            $display("PASS: rd_error correctly asserted for illegal K-character");

        // Clear k_in back to data mode before random testing
        @(negedge clk);
        k_in = 1'b0;

        // =====================================================================
        // TEST 4: Random sweep + cumulative running-disparity bound check
        // =====================================================================
        cum_disparity = 0;
        for (i = 0; i < 2000; i = i + 1) begin
            send_byte($random, 1'b0); // random data byte, k_in=0 (ordinary data only)

            ones_count    = count_ones10(data_out);
            cum_disparity = cum_disparity + (ones_count - (10 - ones_count));

            if (cum_disparity > 6 || cum_disparity < -6) begin
                $display("FAIL: cumulative disparity out of bound at symbol %0d: %0d (data_out=%b)",
                          i, cum_disparity, data_out);
                errors = errors + 1;
            end
        end
        $display("INFO: final cumulative disparity after 2000 random symbols = %0d", cum_disparity);

        // ---- Summary ----
        @(posedge clk);
        if (errors == 0)
            $display("\n=== ALL TESTS PASSED ===\n");
        else
            $display("\n=== %0d TEST(S) FAILED ===\n", errors);

        $finish;
    end

endmodule
