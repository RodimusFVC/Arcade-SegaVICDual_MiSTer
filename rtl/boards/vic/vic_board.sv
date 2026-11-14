//============================================================================
//  vic_board.sv - Sega / Gremlin VIC boards (single-game and Dual Game): CPU bus, video, inputs
//  Copyright (C) 2026 Rodimus
//  Based on MAME vicdual.cpp, vicdual_v.cpp (Zsolt Vasvari, BSD-3-Clause)
//
//  CLK = 30.93696 MHz = 2 x the 15.46848 MHz master: pixel = CLK / 6 (master / 3), Z80 = CLK / 16 (master / 8).
//  Raster 328 x 262, 256 x 224 visible. The vertical counter steps at the end of HSYNC (0x130): visible pixels
//  (h < 0x100) see the row of their line, the 64V / VBLANK comparators read the counter as the hardware does.
//  Video: 32 x 28 characters, code from video RAM, 8 x 8 pattern from character RAM, colour PROM entry
//  {palette bank, code[7:5]}: background = bits 3:1, foreground = bits 7:5 (bit 2 R, bit 1 B, bit 0 G).
//  The next character is fetched while the current one is shifted out (fetch addresses follow h + 1).
//  Memory map (dual-game board): ROM 0x0000-0x3FFF (mirror 0x4000), video RAM 0x8000-0x83FF, work RAM
//  0x8400-0x87FF, character RAM 0x8800-0x8FFF, all RAM mirrored by 0x7000. No interrupts. Single-game boards: per-variant
//  ROM / RAM decode (CPU bus section).
//  I/O (dual-game, Carnival family): IN0-IN3 read at A1:0 (mirror 0x7C); writes decoded per address bit: A3 sets coin
//  status, A6 latches the palette bank, A0 / A1 = sound board latches (port 1 / port 2). Single-game I/O: ports ANDed
//  by address bit, A0 sets coin status. Live port bits (CBLANK / VBLANK / 64V / timer / coin status) leave as `live`
//  and come back through the top level's input map, at the port bit each set reads them on.
//  Coin (in_ports byte 4 bit 0): pulses the CPU reset and clears coin status 70 ms later; the game itself sets
//  coin status through A3. Sidam bootlegs (game_flags2 bit 0): coin pulses NMI instead, sets coin status at once and
//  clears it 10 ms later.
//  4-bit program PROMs (game_flags2 bit 1: Depthcharge older, Sub Hunter): low nibbles at rom0 0x0000, high nibbles at
//  0x2000; rom0_a alternates between the two every clock and both halves are latched; above 0x17FF reads 00.
//  N-Sub (26 upright, single-game I/O; 27 cocktail, dual-game I/O): colour PROM read inverted. 97269-P-B video board:
//  palette writes also latch data bits 3:2; bit 2 set = background pixels take the gradient PROM (rom2 0x100-0x1FF,
//  entry ((x + 5) & 0xFF) / 2, bit 3 -> entry bit 7): high nibble 1 = blue-to-cyan (G 80 + 8 x low, B FF), 4 = black-to-
//  blue (B 11 x low), else the colour PROM background. The starfield PROMs are not used (no circuit known). 97201-P coin
//  calculator: coin 1 / 2 / service edges add credits to a play counter (COINAGE: bits 2:0 coins per credit, bits 5:3
//  credits per coin 2 unless bit 6 = shared with coin 1); every 150 ms one credit becomes a coin pulse.
//  Carnival music board (no schematic): 8035 @ 3.579545 MHz with an AY-3-8912 @ / 3 (variant 16) or a PIT 8253,
//  all three counters @ / 3, gates high, each OUT a 1-bit DAC (variant 17).
//  Sound board 800-3057 (Carnival.man p053-054): music enters at P2-9 through R96 22K into the U8 summer
//  (R67 22K feedback), unity gain. The effect circuits run as a dsnd_engine program (MRA index 5, sources = the two
//  sound latches); the engine output is added to the music. Head On sound board 822-0002 (single VIC boards 4 / 5 / 7 / 8:
//  the I/O A1 write is latched as sound byte 0; dual-game sets use the A0 latch) runs as a dsnd_engine program too, as do
//  the Space Attack Y-2 board (variant 6: A1; Space Attack / Head On: the port 2 latch), Invinco (variant 28: A1) and
//  the Depthcharge board (variant 1: A2) and the Frogs board (variant 3: A1).
//  Pools: z80pa85_0 = main CPU, mcs48_0 = music CPU, jt49_0 = AY, pit8253_0 = PIT, dsnd_0-3 = sound board engines; RAM block 0 = work RAM (port B hiscore),
//  1 = video RAM, 2 = character RAM (port B = video fetch); rom0 = program, rom1 = music program, rom2 = colour PROM
//  (0x000-0x01F) + N-Sub gradient PROM (0x100-0x1FF).
//============================================================================

module vic_board
(
    input  logic        clk,
    input  logic        reset,
    input  logic        pause,
    input  logic  [7:0] variant,
    input  logic  [7:0] game_flags2,     // bit 0: coin on NMI (Sidam bootlegs), bit 1: 4-bit program PROMs
    output logic        ce_pix,

    input  logic [47:0] in_ports,
    output logic  [7:0] live,

    output logic [14:0] rom0_a,
    input  logic  [7:0] rom0_d,
    output logic  [9:0] rom1_a,
    input  logic  [7:0] rom1_d,
    output logic  [8:0] rom2_a,
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

localparam [8:0] HTOTAL  = 9'h148, HBSTART = 9'h100, HSSTART = 9'h110, HSEND = 9'h130;
localparam [8:0] VTOTAL  = 9'h106, VBSTART = 9'h0E0, VSSTART = 9'h0EC;
localparam [16:0] TIMER_2MS = 17'd61874;   // 2 ms at 30.93696 MHz: timer_value_r toggles at 500 ticks / s
localparam [21:0] COIN_70MS = 22'd2165587; // coin switch held closed 70 ms
localparam [21:0] COIN_10MS = 22'd309370;  // Sidam bootlegs: coin status set at once, cleared after 10 ms
localparam [24:0] CLK_HZ    = 25'd30936960;
localparam [24:0] XTAL_HZ   = 25'd3579545; // music board crystal

/////////////////////////////  Clock enables  /////////////////////////////

logic [2:0] pdiv;
logic [3:0] cdiv;
wire        pce = pdiv == 3'd5;

always_ff @(posedge clk) begin
    pdiv <= pce ? 3'd0 : pdiv + 3'd1;
    cdiv <= cdiv + 4'd1;
    if (reset) begin
        pdiv <= '0;
        cdiv <= '0;
    end
end

assign ce_pix = pce;

/////////////////////////////  Raster counters  /////////////////////////////

logic [8:0] h, v;

always_ff @(posedge clk) begin
    if (pce) begin
        h <= h == HTOTAL - 9'd1 ? 9'd0 : h + 9'd1;
        if (h == HSEND - 9'd1) v <= v == VTOTAL - 9'd1 ? 9'd0 : v + 9'd1;
    end
    if (reset) {h, v} <= '0;
end

wire vblank_comp = v < VBSTART;
wire hblank      = h >= HBSTART;
wire cblank_comp = vblank_comp && !hblank;

/////////////////////////////  Video fetch + shifter  /////////////////////////////

logic [1:0] pal_bank;
logic       bw_video;   // B/W monitor: pixel = white / black, no colour PROM (variant table in the CPU bus section)
logic [7:0] nx_data, sh;
logic [2:0] nx_back, nx_fore, back, fore;
wire        v_ns = variant == 8'd26 || variant == 8'd27;    // N-Sub: inverted colour PROM + 97269-P-B gradient
logic [1:0] g_bank;                                         // 97269-P-B latch: palette write data bits 3:2
logic [7:0] g_q;

wire       fetch = (h[2:0] == 3'd7 && h < HBSTART - 9'd1) || h == HTOTAL - 9'd1;
wire [4:0] fcol0 = h == HTOTAL - 9'd1 ? 5'd0 : h[7:3] + 5'd1;
wire [4:0] fcol  = crt_flip ? 5'd31 - fcol0 : fcol0;
wire [7:0] frow  = crt_flip ? 8'd223 - v[7:0] : v[7:0];
wire [7:0] code  = pr_o[1].b_q;
wire [7:0] cdat  = pr_o[2].b_q;

// rom2: colour PROM read for the fetch (address held in pdiv 2-3, data at pdiv 4); gradient PROM read in pdiv 1 (data
// at pdiv 2) for the pixel at h (the gradient board counts the raw raster: flipped with the picture).
wire [7:0] g_x    = (crt_flip ? 8'd255 - h[7:0] : h[7:0]) + 8'd5;
assign rom2_a = pdiv == 3'd1 ? {1'b1, g_bank[1], g_x[7:1]} : {4'd0, pal_bank, code[7:5]};
wire [7:0] cprom  = v_ns ? ~rom2_d : rom2_d;

always_ff @(posedge clk) begin
    if (pdiv == 3'd4 && fetch) begin
        nx_data <= crt_flip ? {cdat[0], cdat[1], cdat[2], cdat[3], cdat[4], cdat[5], cdat[6], cdat[7]} : cdat;
        nx_back <= cprom[3:1];
        nx_fore <= cprom[7:5];
    end
    if (pdiv == 3'd2) g_q <= rom2_d;
end

wire [8:0] hs_at = HSSTART + {{5{h_adj[3]}}, h_adj};
wire [8:0] vs_at = VSSTART + {{5{v_adj[3]}}, v_adj};
wire [2:0] pen   = sh[7] ? fore : back;
wire [8:0] h_nx  = h == HTOTAL - 9'd1 ? 9'd0 : h + 9'd1;
wire       g_cy  = g_q[7:4] == 4'h1;
wire       g_on  = v_ns && g_bank[0] && !sh[7] && (g_cy || g_q[7:4] == 4'h4);

always_ff @(posedge clk) begin
    if (pce) begin
        video_r      <= g_on ? 8'h00 : {8{bw_video ? sh[7] : pen[2]}};
        video_g      <= g_on ? (g_cy ? {1'b1, g_q[3:0], 3'b000} : 8'h00) : {8{bw_video ? sh[7] : pen[0]}};
        video_b      <= g_on ? (g_cy ? 8'hFF : {g_q[3:0], g_q[3:0]}) : {8{bw_video ? sh[7] : pen[1]}};
        video_hblank <= hblank;
        video_vblank <= !vblank_comp;
        video_hs     <= h >= hs_at && h < hs_at + 9'd32;
        video_vs     <= v >= vs_at && v < vs_at + 9'd4;
        if (h_nx < HBSTART && h_nx[2:0] == 3'd0) begin
            sh   <= nx_data;
            back <= nx_back;
            fore <= nx_fore;
        end
        else
            sh <= {sh[6:0], 1'b0};
    end
end

/////////////////////////////  CPU bus  /////////////////////////////

wire [15:0] a      = z80pa85_0_o.a;
wire        mreq   = !z80pa85_0_o.mreq_n;
wire        iorq   = !z80pa85_0_o.iorq_n && z80pa85_0_o.m1_n;
wire        rd     = !z80pa85_0_o.rd_n;
wire        wr     = !z80pa85_0_o.wr_n;

// Single-game VIC boards (Head On I/O): the input ports are ANDed onto the bus by address bit (IN0 = A0; IN1 = A3, or
// IN1 = A2 + IN2 = A3) and writes decode per bit (A0 = coin status, A2 = palette bank where fitted). Variants:
//  depthch (1, 8080), safari (2), frogs (3), headon (4), headons (5), sspaceat (6), headon2 (7), headon2bw (8),
//  digger (9), carnivalh (18, dual-game memory map + Head On I/O), invinco (28).
//  ROM 8 KB mirrored to 0x7FFF: 4-9. RAM at 0xC000-0xFFFF (0x8000-0xBFFF unused): 2, 4-9, 28; safari adds 4 KB at
//  0x8000-0x8FFF (mirror 0x3000, RAM block 3) and has no ROM mirror. B/W video (no colour PROM): 1, 2, 3, 5, 8; headon /
//  sspaceat by the cabinet switch (port 5 bit 0 = 1: B/W).
//  carnivalh protection: a read of 0x4000-0x7FFF returns 02 / 07 / 03 after the last write to 0xE000-0xEFFF was 24 / 66 /
//  48 (else 00); those writes still reach RAM.
//  headonn (10, dual-game I/O): palette bank = I/O A1 data ^ 1, coin status A3.
//  nsub (26): ROM 16 KB mirrored to 0x7FFF, RAM at 0xC000; I/O A0 = coin status, A1 = sound latch, A2 = palette bank.
//  nsubc (27): same memory map, dual-game I/O, palette bank at A1; protection: a write to 0xEBE8 of 24 / 66 sets nprot
//  to 02 / 07 (the write does not reach character RAM), a read of 0x7F00 returns nprot.
wire v_single = (variant >= 8'd1 && variant <= 8'd9) || variant == 8'd18 || variant == 8'd26 || variant == 8'd28;   // Quartus 17: no `inside`
wire v_in1_a2 = (variant >= 8'd6 && variant <= 8'd9) || variant == 8'd28;
wire v_rom8k  = variant >= 8'd4 && variant <= 8'd9;
wire v_c000   = v_rom8k || variant == 8'd2 || variant == 8'd26 || variant == 8'd27 || variant == 8'd28;
wire v_safari = variant == 8'd2;
wire v_carnh  = variant == 8'd18;
wire v_headnn = variant == 8'd10;
wire v_pal_a2 = variant == 8'd9 || variant == 8'd26 || variant == 8'd28;
wire v_nsub   = variant == 8'd26;
wire v_nsubc  = variant == 8'd27;
wire v_hosnd  = (variant >= 8'd3 && variant <= 8'd8) || variant == 8'd28;   // Frogs / Head On / Space Attack / Invinco sound board on I/O A1
wire v_dcsnd  = variant == 8'd1;                                           // Depthcharge sound board on I/O A2
// sound latch 1 power-up / reset value = the idle state of the board it drives: Depthcharge, Frogs and Head On (active
// high) 00, the others FF
wire v_snd_ah = variant == 8'd1 || variant == 8'd3 || variant == 8'd4 || variant == 8'd5 || variant == 8'd7 || variant == 8'd8
             || variant == 8'd10 || variant == 8'd11 || variant == 8'd14;
wire [7:0] snd1_idle = v_snd_ah ? 8'h00 : 8'hFF;
// sound latch 2 reset: Carnival's music CPU held in reset (d4 low); Pulsar's board lines all idle (high)
wire [7:0] snd2_idle = variant == 8'd22 ? 8'hFF : 8'hEF;
wire v_bw    = variant == 8'd1 || variant == 8'd2 || variant == 8'd3 || variant == 8'd5 || variant == 8'd8
             || ((variant == 8'd4 || variant == 8'd6) && in_ports[40]);

assign bw_video = v_bw;

wire        ram    = mreq && a[15] && (!v_c000 || a[14]);
wire        sram   = mreq && v_safari && a[15:14] == 2'b10;
wire        vram   = ram && a[11:10] == 2'b00;
wire        wram   = ram && a[11:10] == 2'b01;
wire        cram   = ram && a[11];

// Per-variant differences on the dual-game board:
//  carhntds / invcarht / wantsega (13): ROM 0x0000-0x7FFF linear (no 0x4000 mirror).
//  tranqgun (19), brdrlinet (20), brdrline family (21), samurai (25): palette bank latched by I/O A1, not A6.
//  heiankyo (23): no palette bank latch (bank 0).
//  Protection: tranqgun: memory reads 0x4000-0x7FFF return tprot at 0x7800, else 0; a write to
//  0x4000 of D8 / 3A / 6A sets tprot to 02 / 01 / 06. brdrlinet: a read of 0x7800 returns tprot; a write to 0xE9A8 of
//  D8 / 3A sets 02 / 01 (and does not reach character RAM). samurai: every write to 0x0000-0x7FFF latches sprot;
//  IN1.1 / IN2.1 / IN3.1 = bits 1-3 of (sprot AB -> 02, 1D -> 0C, else 00).
logic [7:0] tprot, sprot, cprev;
wire v_carhnt  = variant == 8'd13;
wire v_tranq   = variant == 8'd19;
wire v_brdrt   = variant == 8'd20;
wire v_brdr    = variant == 8'd21 || v_brdrt;
wire v_heian   = variant == 8'd23;
wire v_samurai = variant == 8'd25;
wire pal_a1    = v_tranq || v_brdr || v_samurai || v_nsubc;
wire prot_rd   = ((v_tranq || v_carnh) && a[15:14] == 2'b01) || (v_brdrt && a == 16'h7800) || (v_nsubc && a == 16'h7F00);
wire [7:0] prot_d = v_carnh ? (cprev == 8'h24 ? 8'h02 : cprev == 8'h66 ? 8'h07 : cprev == 8'h48 ? 8'h03 : 8'h00) :
                    v_nsubc || a == 16'h7800 ? tprot : 8'h00;
wire [3:0] s_ans  = !v_samurai ? 4'h0 : sprot == 8'hAB ? 4'h2 : sprot == 8'h1D ? 4'hC : 4'h0;

logic        coin_status, timer_bit, coin_d;
logic  [7:0] snd1, snd2;
logic [16:0] tcnt;
logic [21:0] coin_cnt;
logic  [5:0] cpu_rst, cpu_nmi;
wire         coin_nmi = game_flags2[0];

// N-Sub 97201-P coin calculator (both N-Sub sets carry the board): coin 1 / coin 2 / service = COIN port bits 0-2
// (cocktail: coin 1 only, its other COIN bits are unused)
localparam [22:0] PLAY_150MS = 23'd4640544;
logic  [2:0] nc_d, nc_cnt;
logic  [7:0] nc_play;
logic [22:0] nc_tmr;
logic        nc_pulse;
wire   [7:0] coinage = in_ports[47:40];
wire   [2:0] nc_in   = in_ports[34:32] & (v_ns && variant == 8'd27 ? 3'b001 : 3'b111);   // cocktail: coin 1 only
wire   [2:0] nc_rise = nc_in & ~nc_d;
wire         nc_x1   = nc_rise[0] || (nc_rise[1] && coinage[6]);          // a coin on the coins-per-credit counter
wire   [7:0] nc_add  = {7'd0, nc_x1 && nc_cnt == 3'd1} + {7'd0, nc_rise[2]} +
                       (nc_rise[1] && !coinage[6] ? {5'd0, coinage[5:3]} : 8'd0);
always_ff @(posedge clk) begin
    nc_d     <= nc_in;
    nc_pulse <= 1'b0;
    if (nc_x1) nc_cnt <= nc_cnt == 3'd1 ? coinage[2:0] : nc_cnt - 3'd1;
    nc_tmr   <= nc_tmr == PLAY_150MS - 23'd1 ? 23'd0 : nc_tmr + 23'd1;
    if (nc_tmr == 23'd0 && nc_play != 8'd0) begin
        nc_play  <= nc_play - 8'd1 + nc_add;
        nc_pulse <= 1'b1;
    end
    else
        nc_play <= nc_play + nc_add;
    if (reset) begin
        nc_d    <= nc_in;
        nc_cnt  <= coinage[2:0];
        nc_play <= 8'd0;
        nc_tmr  <= '0;
    end
end

wire         coin_in = v_ns ? nc_pulse : in_ports[32];

always_ff @(posedge clk) begin
    coin_d <= coin_in;
    if (cpu_rst != 6'd0) cpu_rst <= cpu_rst - 6'd1;
    if (cpu_nmi != 6'd0) cpu_nmi <= cpu_nmi - 6'd1;
    if (coin_cnt != 22'd0) begin
        coin_cnt <= coin_cnt - 22'd1;
        if (coin_cnt == 22'd1) coin_status <= 1'b0;
    end
    if (coin_in && !coin_d) begin
        if (coin_nmi) begin
            cpu_nmi     <= 6'd63;
            coin_status <= 1'b1;
            coin_cnt    <= COIN_10MS;
        end
        else begin
            cpu_rst  <= 6'd63;
            coin_cnt <= COIN_70MS;
        end
    end
    if (iorq && wr && !v_single) begin
        if (a[0]) snd1        <= z80pa85_0_o.dout;
        if (a[1]) snd2        <= z80pa85_0_o.dout;
        if (a[3]) coin_status <= 1'b1;
        if (v_headnn) begin
            if (a[1]) pal_bank <= z80pa85_0_o.dout[1:0] ^ 2'd1;
        end
        else if (pal_a1 ? a[1] : a[6] && !v_heian) begin
            pal_bank <= z80pa85_0_o.dout[1:0];
            g_bank   <= z80pa85_0_o.dout[3:2];
        end
    end
    if (iorq && wr && v_single) begin
        if (a[0]) coin_status <= 1'b1;
        if (a[1] && (v_nsub || v_hosnd)) snd1 <= z80pa85_0_o.dout;
        if (a[2] && v_dcsnd) snd1 <= z80pa85_0_o.dout;
        if (a[2] && v_pal_a2) begin
            pal_bank <= z80pa85_0_o.dout[1:0];
            g_bank   <= z80pa85_0_o.dout[3:2];
        end
    end
    if (mreq && wr) begin
        if (a[15:12] == 4'hE) cprev <= z80pa85_0_o.dout;
        if ((v_tranq && a == 16'h4000) || (v_brdrt && a == 16'hE9A8))
            case (z80pa85_0_o.dout)
                8'hD8:   tprot <= 8'h02;
                8'h3A:   tprot <= 8'h01;
                8'h6A:   if (v_tranq) tprot <= 8'h06;
                default: ;
            endcase
        if (v_nsubc && a == 16'hEBE8)
            case (z80pa85_0_o.dout)
                8'h24:   tprot <= 8'h02;
                8'h66:   tprot <= 8'h07;
                default: ;
            endcase
        if (!a[15]) sprot <= z80pa85_0_o.dout;
    end
    tcnt <= tcnt == TIMER_2MS - 17'd1 ? 17'd0 : tcnt + 17'd1;
    if (tcnt == TIMER_2MS - 17'd1) timer_bit <= !timer_bit;
    if (reset) begin
        coin_status <= 1'b0;
        coin_d      <= 1'b0;
        coin_cnt    <= '0;
        cpu_rst     <= '0;
        cpu_nmi     <= '0;
        pal_bank    <= 2'd0;
        g_bank      <= 2'd0;
        snd1        <= snd1_idle;
        snd2        <= snd2_idle;
        tcnt        <= '0;
        timer_bit   <= 1'b0;
        tprot       <= 8'h00;
        sprot       <= 8'h00;
        cprev       <= 8'h00;
    end
end

// Live port lines (top level: ctl_port_map DIP lines 8-13, placed by the MRA input map; gen_mra CUSTOM_LINES):
// 0 CBLANK comparator, 1 VBLANK comparator, 2 64V, 3 500 Hz timer, 4 coin status, 5 coin status inverted.
assign live = {2'b00, !coin_status, coin_status, timer_bit, v[6], vblank_comp, cblank_comp};

// Invinco / Deep Scan (variant 12): the fire buttons cross over on this board. The input map puts button 1 on IN0.5 and
// button 2 on IN2.5; the game reads IN2.5 as Deep Scan fire left (and Invinco fire) and IN0.5 as fire right, so the two
// bits swap here: button 1 (A) = fire left / Invinco fire, button 2 (B) = fire right.
// Car Hunt / Deep Scan (variant 13): Deep Scan's fire right is IN0.5, shared with Car Hunt's Up. Button 2 (B) enters on
// the unused IN0.6 and is wired onto IN0.5 too (active low: AND); IN0.6 then reads idle. Wanted (same variant) has no
// button there, so its IN0.6 idles high and IN0.5 is unchanged.
// Depthcharge / older / Sub Hunter (variant 1): the input map puts button 1 on IN0.1 (drop left) and button 2 on IN0.0
// (drop right); the two bits swap here so button 1 (A) drops right and button 2 (B) drops left.
wire       ds_swap = variant == 8'd12;
wire       dc_swap = variant == 8'd1;
wire [7:0] in0     = ds_swap  ? {in_ports[7:6], in_ports[21], in_ports[4:0]}    :
                     dc_swap  ? {in_ports[7:2], in_ports[0], in_ports[1]}       :
                     v_carhnt ? {in_ports[7], 1'b1, in_ports[5] & in_ports[6], in_ports[4:0]} : in_ports[7:0];
wire [7:0] in2     = ds_swap ? {in_ports[23:22], in_ports[5], in_ports[20:16]} : in_ports[23:16];

// Dual-game I/O: IN0-IN3 at A1:0. Single-game I/O: ports ANDed by address bit.
logic [7:0] in_d;
always_comb begin
    case (a[1:0])
        2'd0:    in_d = in0;
        2'd1:    in_d = {in_ports[15:10], v_samurai ? s_ans[1] : in_ports[9],  in_ports[8]};
        2'd2:    in_d = {in2[7:2],        v_samurai ? s_ans[2] : in2[1],       in2[0]};
        default: in_d = {in_ports[31:26], v_samurai ? s_ans[3] : in_ports[25], in_ports[24]};
    endcase
    if (v_single)
        in_d = (a[0] ? in_ports[7:0] : 8'hFF) & ((v_in1_a2 ? a[2] : a[3]) ? in_ports[15:8] : 8'hFF) &
               (v_in1_a2 && a[3] ? in_ports[23:16] : 8'hFF);
end

wire        v_nib = game_flags2[1];
logic       nib_ph;
logic [3:0] nib_lo, nib_hi;
always_ff @(posedge clk) begin
    nib_ph <= !nib_ph;
    if (nib_ph) nib_lo <= rom0_d[3:0];      // read of the low-nibble address issued while nib_ph was 0
    else        nib_hi <= rom0_d[3:0];
end
wire  [7:0] nib_d = a[13] || a[12:11] == 2'b11 ? 8'h00 : {nib_hi, nib_lo};

assign rom0_a = v_nib ? {1'b0, nib_ph, a[12:0]} :
                v_carhnt ? a[14:0] : v_rom8k ? {2'b00, a[12:0]} : {1'b0, a[13:0]};

always_comb begin
    z80pa85_0_i        = '0;
    z80pa85_0_i.cen_p  = !pause && cdiv == 4'd0;
    z80pa85_0_i.cen_n  = !pause && cdiv == 4'd8;
    z80pa85_0_i.wait_n = 1'b1;
    z80pa85_0_i.int_n  = 1'b1;
    z80pa85_0_i.nmi_n  = cpu_nmi == 6'd0;
    z80pa85_0_i.i8080  = variant == 8'd1;
    z80pa85_0_i.rst    = cpu_rst != 6'd0;
    z80pa85_0_i.di     = iorq ? in_d :
                         prot_rd ? prot_d :
                         !a[15] ? (v_nib ? nib_d : rom0_d) :
                         sram ? pr_o[3].a_q :
                         a[11] ? pr_o[2].a_q :
                         a[10] ? pr_o[0].a_q : pr_o[1].a_q;
end

/////////////////////////////  Board RAM (pool)  /////////////////////////////

always_comb begin
    pr_i = '0;
    pr_i[0].a_addr = {6'd0, a[9:0]};
    pr_i[0].a_d    = z80pa85_0_o.dout;
    pr_i[0].a_we   = wram && wr;
    pr_i[0].b_addr = {6'd0, hs_address[9:0]};
    pr_i[0].b_d    = hs_data_in;
    pr_i[0].b_we   = hs_write;
    pr_i[1].a_addr = {6'd0, a[9:0]};
    pr_i[1].a_d    = z80pa85_0_o.dout;
    pr_i[1].a_we   = vram && wr;
    pr_i[1].b_addr = {6'd0, frow[7:3], fcol};
    pr_i[2].a_addr = {5'd0, a[10:0]};
    pr_i[2].a_d    = z80pa85_0_o.dout;
    pr_i[2].a_we   = cram && wr && !(v_brdrt && a == 16'hE9A8) && !(v_nsubc && a == 16'hEBE8);
    pr_i[2].b_addr = {5'd0, code, frow[2:0]};
    pr_i[3].a_addr = {4'd0, a[11:0]};
    pr_i[3].a_d    = z80pa85_0_o.dout;
    pr_i[3].a_we   = sram && wr;
end

assign hs_data_out = pr_o[0].b_q;

/////////////////////////////  Carnival music board  /////////////////////////////

// Port 2 (snd2): d3 = T1 (inverted), d4 = 8035 reset (0 = held). The latches survive the coin CPU reset.
// U63 / U64 are 74LS374 (no clear): power-up contents undefined; idle values used: no active-low effect trigger
// asserted, 8035 held until the game's first port 2 write.
// 8035 P1 = AY data bus, P2 d6 = BDIR, d7 = BC1: BDIR + BC1 latches the address (selected while the upper
// nibble is 0), BDIR alone writes the selected register. jt49 restarts the envelope on the write edge only.
// PIT version: P1 = PIT data bus, P2 d7 rising = write strobe, P2 d6:5 = A1:A0.
wire mus_ay  = variant == 8'd16;
wire mus_pit = variant == 8'd17;
wire music   = mus_ay || mus_pit;

logic [24:0] xacc;
logic        xce;
logic  [1:0] ay_div;
logic  [3:0] ay_addr;
logic        ay_active;
logic        pit_wr_d;
wire   [7:0] mp1 = mcs48_0_o.p1;
wire   [7:0] mp2 = mcs48_0_o.p2;

always_ff @(posedge clk) begin
    xce <= 1'b0;
    if (!pause) begin
        if (xacc >= CLK_HZ - XTAL_HZ) begin
            xacc <= xacc - (CLK_HZ - XTAL_HZ);
            xce  <= 1'b1;
        end
        else
            xacc <= xacc + XTAL_HZ;
    end
    if (xce) ay_div <= ay_div == 2'd2 ? 2'd0 : ay_div + 2'd1;
    if (mp2[6] && mp2[7]) begin
        ay_addr   <= mp1[3:0];
        ay_active <= mp1[7:4] == 4'd0;
    end
    pit_wr_d <= mp2[7];
    if (reset) begin
        pit_wr_d  <= 1'b1;
        xacc      <= '0;
        ay_div    <= '0;
        ay_addr   <= '0;
        ay_active <= 1'b0;
    end
end

assign rom1_a = mcs48_0_o.pmem_a[9:0];

always_comb begin
    mcs48_0_i         = '0;
    mcs48_0_i.reset_n = music && snd2[4];
    mcs48_0_i.xtal_en = xce;
    mcs48_0_i.int_n   = 1'b1;
    mcs48_0_i.t1      = !snd2[3];
    mcs48_0_i.p1_in   = mp1;
    mcs48_0_i.p2_in   = mp2;
    mcs48_0_i.db      = 8'hFF;
    mcs48_0_i.pmem_d  = rom1_d;

    jt49_0_i          = '0;
    jt49_0_i.rst_n    = mus_ay && !reset;
    jt49_0_i.ce       = xce && ay_div == 2'd0;
    jt49_0_i.addr     = ay_addr;
    jt49_0_i.cs_n     = !(mp2[6] && !mp2[7] && ay_active);
    jt49_0_i.wr_n     = !(mp2[6] && !mp2[7]);
    jt49_0_i.din      = mp1;

    pit8253_0_i        = '0;
    pit8253_0_i.rst    = !mus_pit || reset;
    pit8253_0_i.wr_en  = mus_pit && mp2[7] && !pit_wr_d;
    pit8253_0_i.a      = mp2[6:5];
    pit8253_0_i.din    = mp1;
    pit8253_0_i.clk_ce = xce && ay_div == 2'd0;
    pit8253_0_i.gate   = 3'b111;
end

// U8 summer: music (R96 22K / R67 22K) at unity; jt49 A+B+C (0-765) scaled to leave room for the effects.
// PIT DACs: 0.6 x one full-scale AY channel each (the AY / DAC level ratio of the reference; no music board schematic).
localparam [15:0] PIT_LVL = 16'd2448;
wire [15:0] pit_mix = (pit8253_0_o.out[0] ? PIT_LVL : 16'd0) + (pit8253_0_o.out[1] ? PIT_LVL : 16'd0) +
                      (pit8253_0_o.out[2] ? PIT_LVL : 16'd0);
wire signed [15:0] mus = mus_pit ? $signed(pit_mix) : $signed({2'b00, jt49_0_o.sound, 4'd0});

// dsnd sources: byte 0 = port 1 latch, byte 1 = port 2 latch; over the last sample period: byte 2 = port 1 bits that
// were high at any time, byte 3 = port 1 bits that were low at any time, byte 4 = the same for port 2; byte 5 bit 0 =
// IN3 bit 4 (Game Select on the dual-game sets: its second pole picks which sound board reaches the amplifier). The games pulse
// some triggers for a few microseconds (Head On CRASH high, Carnival rifle / clang low): the sound boards' 555s and
// stretchers catch them, one read per engine sample (33 us) would not.
logic [7:0] snd1_or, snd1_seen, snd1_and, snd1_low, snd2_and, snd2_low;
always_ff @(posedge clk) begin
    if (reset) begin
        snd1_seen <= snd1_idle;             // as the latches' reset values: no trigger reads as pulsed at power-up
        snd1_or   <= snd1_idle;
        snd1_low  <= 8'hFF;
        snd1_and  <= 8'hFF;
        snd2_low  <= 8'hFF;
        snd2_and  <= 8'hFF;
    end
    else if (dsnd_0_o.sample) begin
        snd1_seen <= snd1_or | snd1;
        snd1_low  <= snd1_and & snd1;
        snd2_low  <= snd2_and & snd2;
        snd1_or   <= snd1;
        snd1_and  <= snd1;
        snd2_and  <= snd2;
    end
    else begin
        snd1_or  <= snd1_or | snd1;
        snd1_and <= snd1_and & snd1;
        snd2_and <= snd2_and & snd2;
    end
end
// A sound board too big for one engine runs as up to four programs on dsnd_0-3 (same sources, outputs summed).
assign dsnd_0_i.src = {16'd0, 7'd0, in_ports[28], snd2_low, snd1_low, snd1_seen, snd2, snd1};
assign dsnd_1_i.src = dsnd_0_i.src;
assign dsnd_2_i.src = dsnd_0_i.src;
assign dsnd_3_i.src = dsnd_0_i.src;

wire signed [17:0] mix = mus + $signed(dsnd_0_o.out) + $signed(dsnd_1_o.out) + $signed(dsnd_2_o.out)
                       + $signed(dsnd_3_o.out);
assign audio = mix > 18'sd32767 ? 16'sd32767 : mix < -18'sd32768 ? 16'sh8000 : mix[15:0];

endmodule
