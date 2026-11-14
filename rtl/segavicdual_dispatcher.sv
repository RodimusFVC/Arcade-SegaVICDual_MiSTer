//============================================================================
//  segavicdual_dispatcher - SegaVICDual shared pools and board select
//  Copyright (C) 2026 Rodimus
//============================================================================

module segavicdual_dispatcher
(
    input  logic        clk,
    input  logic        reset,
    input  logic        pause,
    input  logic  [7:0] variant,
    input  logic  [7:0] core_byte,
    input  logic  [7:0] game_flags2,
    output logic        ce_pix,

    input  logic [47:0] in_ports,
    output logic  [7:0] live,           // board live port lines (vic_board), DIP lines 8-15 in the top level

    input  logic [24:0] ioctl_addr,
    input  logic  [7:0] ioctl_dout,
    input  logic        ioctl_wr0,
    input  logic        ds_wr,          // MRA index 5: discrete sound programs, 8 KB per engine (ds_addr[14:13])
    input  logic [14:0] ds_addr,
    input  logic  [7:0] ds_data,
    input  logic  [3:0] ds_on,          // per engine: a program arrived with this game

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

    output logic signed [15:0] audio_l,
    output logic signed [15:0] audio_r,

    input  logic [15:0] hs_address,
    input  logic  [7:0] hs_data_in,
    output logic  [7:0] hs_data_out,
    input  logic        hs_write
);

wire is_tc  = variant == 8'd0;
wire is_vic = variant != 8'd0;

/////////////////////////////  Shared CPU / sound chip pool  /////////////////////////////

//   z80pa85_0  main CPU, every set (Z80; i8080 = 1 on the Depthcharge / Sub Hunter board)
//   mcs48_0    Carnival music CPU (8035, 64 B RAM, program = rom1)
//   jt49_0     Carnival AY-3-8912 music (carnivalb: the PIT 8253 slot below)
//   pit8253_0  Carnival (PIT 8253 music, carnivalb): write-only, one clock for all three counters (cs / rd / dout tied)
//   dsnd_0-3   discrete sound boards (programs = MRA index 5, 8 KB slot each), TICK 1024 = 30.212 kHz; each out muted
//              unless its ds_on bit is set; a board too big for one engine's 410-unit budget runs on several
chip_pool_pkg::z80pa85_i_t z80pa85_0_i;
chip_pool_pkg::z80pa85_o_t z80pa85_0_o;
chip_pool_pkg::mcs48_i_t   mcs48_0_i;
chip_pool_pkg::mcs48_o_t   mcs48_0_o;
chip_pool_pkg::jt49_i_t    jt49_0_i;
chip_pool_pkg::jt49_o_t    jt49_0_o;
chip_pool_pkg::pit8253_i_t pit8253_0_i;
chip_pool_pkg::pit8253_o_t pit8253_0_o;
chip_pool_pkg::dsnd_i_t    dsnd_0_i;
chip_pool_pkg::dsnd_o_t    dsnd_0_o, dsnd_0_q;
chip_pool_pkg::dsnd_i_t    dsnd_1_i;
chip_pool_pkg::dsnd_o_t    dsnd_1_o, dsnd_1_q;
chip_pool_pkg::dsnd_i_t    dsnd_2_i;
chip_pool_pkg::dsnd_o_t    dsnd_2_o, dsnd_2_q;
chip_pool_pkg::dsnd_i_t    dsnd_3_i;
chip_pool_pkg::dsnd_o_t    dsnd_3_o, dsnd_3_q;

t80sv_z80pa85 z80pa85_0
(
    .clk(clk), .reset_n(~(reset | z80pa85_0_i.rst)), .i(z80pa85_0_i), .o(z80pa85_0_o)
);

t48sv_mcs48_pool #(.RAM_AW(6)) mcs48_0
(
    .clk(clk), .i(mcs48_0_i), .o(mcs48_0_o)
);

jt49 jt49_0
(
    .rst_n(jt49_0_i.rst_n), .clk(clk), .clk_en(jt49_0_i.ce), .addr(jt49_0_i.addr), .cs_n(jt49_0_i.cs_n),
    .wr_n(jt49_0_i.wr_n), .din(jt49_0_i.din), .sel(1'b1), .dout(), .sound(jt49_0_o.sound),
    .A(jt49_0_o.a), .B(jt49_0_o.b), .C(jt49_0_o.c), .sample(),
    .IOA_in(8'h00), .IOA_out(), .IOA_oe(), .IOB_in(8'h00), .IOB_out(), .IOB_oe()
);

pit8253 pit8253_0
(
    .clk(clk), .rst(pit8253_0_i.rst), .cs(1'b1), .wr(pit8253_0_i.wr_en), .rd(1'b0),
    .a(pit8253_0_i.a), .din(pit8253_0_i.din), .dout(),
    .clk_ce({3{pit8253_0_i.clk_ce}}), .gate(pit8253_0_i.gate), .out(pit8253_0_o.out)
);

dsnd_engine #(.TICK(1024)) dsnd_0
(
    .clk(clk), .reset(reset), .pause(pause),
    .prog_wr(ds_wr && ds_addr[14:13] == 2'd0), .prog_addr(ds_addr[12:0]), .prog_data(ds_data),
    .src(dsnd_0_i.src),
    .out(dsnd_0_q.out), .out_r(dsnd_0_q.out_r), .sample(dsnd_0_q.sample)
);

always_comb begin
    dsnd_0_o        = dsnd_0_q;
    dsnd_0_o.out    = ds_on[0] ? dsnd_0_q.out   : 16'd0;
    dsnd_0_o.out_r  = ds_on[0] ? dsnd_0_q.out_r : 16'd0;
end

dsnd_engine #(.TICK(1024)) dsnd_1
(
    .clk(clk), .reset(reset), .pause(pause),
    .prog_wr(ds_wr && ds_addr[14:13] == 2'd1), .prog_addr(ds_addr[12:0]), .prog_data(ds_data),
    .src(dsnd_1_i.src),
    .out(dsnd_1_q.out), .out_r(dsnd_1_q.out_r), .sample(dsnd_1_q.sample)
);

always_comb begin
    dsnd_1_o        = dsnd_1_q;
    dsnd_1_o.out    = ds_on[1] ? dsnd_1_q.out   : 16'd0;
    dsnd_1_o.out_r  = ds_on[1] ? dsnd_1_q.out_r : 16'd0;
end

dsnd_engine #(.TICK(1024)) dsnd_2
(
    .clk(clk), .reset(reset), .pause(pause),
    .prog_wr(ds_wr && ds_addr[14:13] == 2'd2), .prog_addr(ds_addr[12:0]), .prog_data(ds_data),
    .src(dsnd_2_i.src),
    .out(dsnd_2_q.out), .out_r(dsnd_2_q.out_r), .sample(dsnd_2_q.sample)
);

always_comb begin
    dsnd_2_o        = dsnd_2_q;
    dsnd_2_o.out    = ds_on[2] ? dsnd_2_q.out   : 16'd0;
    dsnd_2_o.out_r  = ds_on[2] ? dsnd_2_q.out_r : 16'd0;
end

dsnd_engine #(.TICK(1024)) dsnd_3
(
    .clk(clk), .reset(reset), .pause(pause),
    .prog_wr(ds_wr && ds_addr[14:13] == 2'd3), .prog_addr(ds_addr[12:0]), .prog_data(ds_data),
    .src(dsnd_3_i.src),
    .out(dsnd_3_q.out), .out_r(dsnd_3_q.out_r), .sample(dsnd_3_q.sample)
);

always_comb begin
    dsnd_3_o        = dsnd_3_q;
    dsnd_3_o.out    = ds_on[3] ? dsnd_3_q.out   : 16'd0;
    dsnd_3_o.out_r  = ds_on[3] ? dsnd_3_q.out_r : 16'd0;
end

/////////////////////////////  Shared ROM blocks  /////////////////////////////

//   index 0, linear: rom0 0x0000-0x7FFF main (0x0000 / 0x2000 = 4-bit PROM low / high nibbles on Depthcharge older / Sub Hunter),
//   rom1 0x8000-0x83FF audio CPU, rom2 0x8400-0x85FF: colour PROM 0x8400-0x841F, N-Sub 97269-P-B gradient PROM 0x8500-0x85FF
localparam int ROM0_AW = 15;
localparam int ROM1_AW = 10;
localparam int ROM2_AW = 9;

logic [ROM0_AW-1:0] tc_rom0_a, vic_rom0_a, rom0_a;
logic [ROM1_AW-1:0] vic_rom1_a, rom1_a;
logic [ROM2_AW-1:0] vic_rom2_a, rom2_a;
logic  [7:0] rom0_d, rom1_d, rom2_d;

assign rom0_a = is_tc ? tc_rom0_a : vic_rom0_a;
assign rom1_a = vic_rom1_a;
assign rom2_a = vic_rom2_a;

dpram_dc #(.widthad_a(ROM0_AW)) rom0
(
    .clock_a(clk), .address_a(ioctl_addr[ROM0_AW-1:0]), .data_a(ioctl_dout), .wren_a(ioctl_wr0 && ioctl_addr[24:ROM0_AW] == '0),
    .q_a(),
    .clock_b(clk), .address_b(rom0_a), .data_b(8'd0), .wren_b(1'b0),
    .q_b(rom0_d)
);

dpram_dc #(.widthad_a(ROM1_AW)) rom1
(
    .clock_a(clk), .address_a(ioctl_addr[ROM1_AW-1:0]), .data_a(ioctl_dout), .wren_a(ioctl_wr0 && ioctl_addr[24:ROM1_AW] == 15'h0020),
    .q_a(),
    .clock_b(clk), .address_b(rom1_a), .data_b(8'd0), .wren_b(1'b0),
    .q_b(rom1_d)
);

dpram_dc #(.widthad_a(ROM2_AW)) rom2
(
    .clock_a(clk), .address_a(ioctl_addr[ROM2_AW-1:0]), .data_a(ioctl_dout), .wren_a(ioctl_wr0 && ioctl_addr[24:ROM2_AW] == 16'h0042),
    .q_a(),
    .clock_b(clk), .address_b(rom2_a), .data_b(8'd0), .wren_b(1'b0),
    .q_b(rom2_d)
);

/////////////////////////////  Shared RAM pool  /////////////////////////////

//   block 0 (1K)  work RAM, port B = hiscore (all boards)
//   block 1 (1K)  video RAM: A = CPU, B = video fetch (all boards)
//   block 2 (2K)  character RAM: A = CPU, B = video fetch (all boards)
//   block 3 (4K)  Safari extra RAM 0x8000-0x8FFF (other boards: unused)
//   block 0 is 2K while the test card (block 0, 11 bits) is wired; 1K once it is deleted
localparam int RAM_BLOCKS = 4;

ram_pool_pkg::pram_i_t [RAM_BLOCKS-1:0] tc_pr_i, vic_pr_i, pool_i;
ram_pool_pkg::pram_o_t [RAM_BLOCKS-1:0] pool_o;

always_comb begin
    pool_i = '0;
    if (is_tc)  pool_i = tc_pr_i;
    if (is_vic) pool_i = vic_pr_i;
end

function automatic int ram_aw(input int n);
    case (n)
        0:       ram_aw = 11;
        1:       ram_aw = 10;
        2:       ram_aw = 11;
        default: ram_aw = 12;
    endcase
endfunction

genvar pn;
generate
    for (pn = 0; pn < RAM_BLOCKS; pn = pn + 1) begin : rpool
        localparam int AW = ram_aw(pn);
        dpram_dc #(.widthad_a(AW)) ram
        (
            .clock_a(clk), .address_a(pool_i[pn].a_addr[AW-1:0]), .data_a(pool_i[pn].a_d), .wren_a(pool_i[pn].a_we),
            .q_a(pool_o[pn].a_q),
            .clock_b(clk), .address_b(pool_i[pn].b_addr[AW-1:0]), .data_b(pool_i[pn].b_d), .wren_b(pool_i[pn].b_we),
            .q_b(pool_o[pn].b_q)
        );
    end
endgenerate

/////////////////////////////  Boards  /////////////////////////////

logic        tc_ce, tc_hs, tc_vs, tc_hb, tc_vb;
logic  [7:0] tc_r, tc_g, tc_b, tc_hs_d;
logic [11:0] tc_rom_a;
logic signed [15:0] tc_audio;
ram_pool_pkg::pram_i_t [0:0] tc_pr_i0;

assign tc_rom0_a = ROM0_AW'(tc_rom_a);
assign tc_pr_i   = {{(RAM_BLOCKS-1){ram_pool_pkg::pram_i_t'(0)}}, tc_pr_i0};

testcard_board testcard
(
    .clk(clk),
    .reset(reset | ~is_tc),
    .pause(pause),
    .ce_pix(tc_ce),
    .in_ports(in_ports),
    .rom_a(tc_rom_a),
    .rom_d(rom0_d),
    .crt_flip(crt_flip),
    .h_adj(h_adj),
    .v_adj(v_adj),
    .video_r(tc_r),
    .video_g(tc_g),
    .video_b(tc_b),
    .video_hs(tc_hs),
    .video_vs(tc_vs),
    .video_hblank(tc_hb),
    .video_vblank(tc_vb),
    .audio(tc_audio),
    .hs_address(hs_address),
    .hs_data_in(hs_data_in),
    .hs_data_out(tc_hs_d),
    .hs_write(hs_write),
    .pr_i(tc_pr_i0),
    .pr_o(pool_o[0:0])
);

//   vic board, variants 1-28 (Carnival family I/O so far)
chip_pool_pkg::z80pa85_i_t vic_z80pa85_0_i;
chip_pool_pkg::mcs48_i_t   vic_mcs48_0_i;
chip_pool_pkg::jt49_i_t    vic_jt49_0_i;
chip_pool_pkg::pit8253_i_t vic_pit8253_0_i;
chip_pool_pkg::dsnd_i_t    vic_dsnd_0_i;
chip_pool_pkg::dsnd_i_t    vic_dsnd_1_i;
chip_pool_pkg::dsnd_i_t    vic_dsnd_2_i;
chip_pool_pkg::dsnd_i_t    vic_dsnd_3_i;
logic        vic_ce, vic_hs, vic_vs, vic_hb, vic_vb;
logic  [7:0] vic_r, vic_g, vic_b, vic_hs_d, vic_live;
logic signed [15:0] vic_audio;

vic_board vic
(
    .clk(clk),
    .reset(reset | ~is_vic),
    .pause(pause),
    .variant(variant),
    .game_flags2(game_flags2),
    .ce_pix(vic_ce),
    .in_ports(in_ports),
    .live(vic_live),
    .rom0_a(vic_rom0_a),
    .rom0_d(rom0_d),
    .rom1_a(vic_rom1_a),
    .rom1_d(rom1_d),
    .rom2_a(vic_rom2_a),
    .rom2_d(rom2_d),
    .z80pa85_0_i(vic_z80pa85_0_i),
    .z80pa85_0_o(z80pa85_0_o),
    .mcs48_0_i(vic_mcs48_0_i),
    .mcs48_0_o(mcs48_0_o),
    .jt49_0_i(vic_jt49_0_i),
    .jt49_0_o(jt49_0_o),
    .pit8253_0_i(vic_pit8253_0_i),
    .pit8253_0_o(pit8253_0_o),
    .dsnd_0_i(vic_dsnd_0_i),
    .dsnd_0_o(dsnd_0_o),
    .dsnd_1_i(vic_dsnd_1_i),
    .dsnd_1_o(dsnd_1_o),
    .dsnd_2_i(vic_dsnd_2_i),
    .dsnd_2_o(dsnd_2_o),
    .dsnd_3_i(vic_dsnd_3_i),
    .dsnd_3_o(dsnd_3_o),
    .crt_flip(crt_flip),
    .h_adj(h_adj),
    .v_adj(v_adj),
    .video_r(vic_r),
    .video_g(vic_g),
    .video_b(vic_b),
    .video_hs(vic_hs),
    .video_vs(vic_vs),
    .video_hblank(vic_hb),
    .video_vblank(vic_vb),
    .audio(vic_audio),
    .hs_address(hs_address),
    .hs_data_in(hs_data_in),
    .hs_data_out(vic_hs_d),
    .hs_write(hs_write),
    .pr_i(vic_pr_i),
    .pr_o(pool_o)
);

always_comb begin
    z80pa85_0_i = '0;
    mcs48_0_i   = '0;
    jt49_0_i    = '0;
    pit8253_0_i = '0;
    dsnd_0_i    = '0;
    dsnd_1_i    = '0;
    dsnd_2_i    = '0;
    dsnd_3_i    = '0;
    if (is_vic) begin
        z80pa85_0_i = vic_z80pa85_0_i;
        mcs48_0_i   = vic_mcs48_0_i;
        jt49_0_i    = vic_jt49_0_i;
        pit8253_0_i = vic_pit8253_0_i;
        dsnd_0_i    = vic_dsnd_0_i;
        dsnd_1_i    = vic_dsnd_1_i;
        dsnd_2_i    = vic_dsnd_2_i;
        dsnd_3_i    = vic_dsnd_3_i;
    end
end

assign ce_pix       = is_tc ? tc_ce : is_vic ? vic_ce : 1'b0;
assign live         = is_vic ? vic_live : 8'd0;
assign video_r      = is_tc ? tc_r  : is_vic ? vic_r  : 8'd0;
assign video_g      = is_tc ? tc_g  : is_vic ? vic_g  : 8'd0;
assign video_b      = is_tc ? tc_b  : is_vic ? vic_b  : 8'd0;
assign video_hs     = is_tc ? tc_hs : is_vic ? vic_hs : 1'b0;
assign video_vs     = is_tc ? tc_vs : is_vic ? vic_vs : 1'b0;
assign video_hblank = is_tc ? tc_hb : is_vic ? vic_hb : 1'b1;
assign video_vblank = is_tc ? tc_vb : is_vic ? vic_vb : 1'b1;
assign audio_l      = is_tc ? tc_audio : is_vic ? vic_audio : 16'sd0;
assign audio_r      = is_tc ? tc_audio : is_vic ? vic_audio : 16'sd0;
assign hs_data_out  = is_tc ? tc_hs_d : is_vic ? vic_hs_d : 8'd0;

endmodule
