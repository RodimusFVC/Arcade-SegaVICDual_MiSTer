//============================================================================
//  testcard_board.sv - SegaVICDual placeholder board from the RodimusCoresMaster template
//  Copyright (C) 2026 Rodimus
//============================================================================

module testcard_board
(
    input  logic        clk,
    input  logic        reset,
    input  logic        pause,
    output logic        ce_pix,

    input  logic [47:0] in_ports,

    output logic [11:0] rom_a,
    input  logic  [7:0] rom_d,

    input  logic        crt_flip,
    input  logic  [3:0] h_adj,
    input  logic  [3:0] v_adj,

    output logic  [7:0] video_r,
    output logic  [7:0] video_g,
    output logic  [7:0] video_b,
    output logic        video_hs,
    output logic        video_vs,
    output logic        video_hblank,
    output logic        video_vblank,

    output logic signed [15:0] audio,

    input  logic [15:0] hs_address,
    input  logic  [7:0] hs_data_in,
    output logic  [7:0] hs_data_out,
    input  logic        hs_write,

    output ram_pool_pkg::pram_i_t [0:0] pr_i,
    input  ram_pool_pkg::pram_o_t [0:0] pr_o
);

logic [2:0] div;   // /5: 6.19 MHz pixel at 30.93696 MHz, 14.6 kHz, 55.7 Hz
logic [8:0] hc, vc;
wire  [8:0] hs_at = 9'd296 + {{5{h_adj[3]}}, h_adj};
wire  [8:0] vs_at = 9'd240 + {{5{v_adj[3]}}, v_adj};

always_ff @(posedge clk) begin
    div    <= div == 3'd4 ? 3'd0 : div + 3'd1;
    ce_pix <= div == 3'd0;
    if (div == 3'd0) begin
        hc <= hc == 9'd423 ? 9'd0 : hc + 9'd1;
        if (hc == 9'd423) vc <= vc == 9'd261 ? 9'd0 : vc + 9'd1;
    end
    if (reset) {div, hc, vc} <= '0;
end

wire [7:0] x = crt_flip ? 8'd255 - hc[7:0] : hc[7:0];
wire [7:0] y = crt_flip ? 8'd223 - vc[7:0] : vc[7:0];
wire       border = x == 8'd0 || x == 8'd255 || y == 8'd0 || y == 8'd223;
wire       marker = x < 8'd24 && y < 8'd24;
wire       held   = |(in_ports[7:0] ^ 8'hFF);

always_ff @(posedge clk) if (ce_pix) begin
    video_hblank <= hc >= 9'd256;
    video_vblank <= vc >= 9'd224;
    video_hs     <= hc >= hs_at && hc < hs_at + 9'd32;
    video_vs     <= vc >= vs_at && vc < vs_at + 9'd3;
    if (border || marker)
        {video_r, video_g, video_b} <= marker ? 24'hFF0000 : 24'hFFFFFF;
    else begin
        video_r <= x[7] ? 8'hC0 : 8'h00;
        video_g <= x[6] ^ held ? 8'hC0 : 8'h00;
        video_b <= x[5] ? 8'hC0 : 8'h00;
    end
end

assign rom_a       = '0;
assign audio       = 16'sd0;
assign hs_data_out = pr_o[0].b_q;
always_comb begin
    pr_i = '0;
    pr_i[0].b_addr = hs_address;
    pr_i[0].b_d    = hs_data_in;
    pr_i[0].b_we   = hs_write;
end

endmodule
