//============================================================================
//  board_template.sv - SegaVICDual board template (NOT in files.qip, never compiled).
//  Copyright (C) 2026 Rodimus
//
//  Boards never instantiate a CPU, sound chip, ROM store or board RAM. Drive the pool ports. Copy this file to start a board.
//  Pools: rtl/segavicdual_dispatcher.sv (chip_pool_pkg slots, Shared ROM blocks, Shared RAM pool rpool).
//  Boards go in rtl/boards/<board>/; replace the board's tie-off in the dispatcher.
//  Add one output chip_pool_pkg::<chip>_i_t <chip>_<n>_i / input chip_pool_pkg::<chip>_o_t <chip>_<n>_o pair per pool slot,
//  pr_i / pr_o are RAM_BLOCKS wide; rom0 / rom1 / rom2 are the dispatcher's Shared ROM blocks.
//  CRT Flip is mandatory: crt_flip mirrors the picture 180 degrees inside the board (HDMI follows).
//============================================================================

module board_template
(
    input  logic        clk,
    input  logic        reset,
    input  logic        pause,
    output logic        ce_pix,

    input  logic [47:0] in_ports,

    output logic [14:0] rom0_a,
    input  logic  [7:0] rom0_d,
    output logic  [9:0] rom1_a,
    input  logic  [7:0] rom1_d,
    output logic  [4:0] rom2_a,
    input  logic  [7:0] rom2_d,

    output chip_pool_pkg::z80pa85_i_t z80pa85_0_i,
    input  chip_pool_pkg::z80pa85_o_t z80pa85_0_o,
    output chip_pool_pkg::mcs48_i_t   mcs48_0_i,
    input  chip_pool_pkg::mcs48_o_t   mcs48_0_o,
    output chip_pool_pkg::jt49_i_t    jt49_0_i,
    input  chip_pool_pkg::jt49_o_t    jt49_0_o,
    output chip_pool_pkg::pit8253_i_t pit8253_0_i,
    input  chip_pool_pkg::pit8253_o_t pit8253_0_o,
    output chip_pool_pkg::dsnd_i_t    dsnd_0_i,
    input  chip_pool_pkg::dsnd_o_t    dsnd_0_o,
    output chip_pool_pkg::dsnd_i_t    dsnd_1_i,
    input  chip_pool_pkg::dsnd_o_t    dsnd_1_o,
    output chip_pool_pkg::dsnd_i_t    dsnd_2_i,
    input  chip_pool_pkg::dsnd_o_t    dsnd_2_o,
    output chip_pool_pkg::dsnd_i_t    dsnd_3_i,
    input  chip_pool_pkg::dsnd_o_t    dsnd_3_o,

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

    output ram_pool_pkg::pram_i_t [3:0] pr_i,
    input  ram_pool_pkg::pram_o_t [3:0] pr_o
);

assign ce_pix       = 1'b0;
assign rom0_a       = '0;
assign rom1_a       = '0;
assign rom2_a       = '0;
assign z80pa85_0_i  = '0;
assign mcs48_0_i    = '0;
assign jt49_0_i     = '0;
assign pit8253_0_i  = '0;
assign dsnd_0_i     = '0;
assign dsnd_1_i     = '0;
assign dsnd_2_i     = '0;
assign dsnd_3_i     = '0;
assign video_r      = 8'd0;
assign video_g      = 8'd0;
assign video_b      = 8'd0;
assign video_hs     = 1'b0;
assign video_vs     = 1'b0;
assign video_hblank = 1'b1;
assign video_vblank = 1'b1;
assign audio        = 16'sd0;
assign hs_data_out  = 8'd0;
assign pr_i         = '0;

endmodule
