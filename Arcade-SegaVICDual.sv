//============================================================================
//
//  SegaVICDual: arcade hardware for MiSTer
//  Copyright (C) 2026 Rodimus
//
//  Top level from the RodimusCoresMaster template (Konami82 / Pac-Man lineage, MikeJ / Sorgelig)
//
//  Permission is hereby granted, free of charge, to any person obtaining a
//  copy of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
//  DEALINGS IN THE SOFTWARE.
//
//============================================================================

module emu
(
    `include "sys/emu_ports.vh"
);

wire        CLK_SYS;
wire        locked;
wire [127:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire [10:0] ps2_key;
wire        ioctl_download;
wire        ioctl_upload;
wire        ioctl_upload_req;
wire  [7:0] ioctl_din;
wire        ioctl_wr;
wire  [7:0] ioctl_index;
wire [26:0] ioctl_addr27;
wire [24:0] ioctl_addr = ioctl_addr27[24:0];
wire  [7:0] ioctl_dout;
wire [15:0] joystick_0, joystick_1;
wire [15:0] joystick_r_analog_0, joystick_r_analog_1;
wire [21:0] gamma_bus;
wire        direct_video;
wire        video_rotated;
wire        pause_cpu;
wire        hblank, vblank;

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign FB_FORCE_BLANK = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

wire signed [15:0] audio_l, audio_r;
assign AUDIO_L = pause_cpu ? 16'd0 : audio_l;
assign AUDIO_R = pause_cpu ? 16'd0 : audio_r;
assign AUDIO_S = 1;
assign AUDIO_MIX = 0;

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign LED_USER  = ioctl_download;
assign BUTTONS = 0;

reg [7:0] game_var    = 8'd0;
reg [7:0] game_flags  = 8'h90;
reg [7:0] core_byte   = 8'd0;
reg [7:0] game_flags2 = 8'd0;
reg [6:0] in_map[48];                                   // {DIP-line flag (map bit 7), control id / line}
reg [7:0] port_idle[6] = '{8'hFF,8'hFF,8'hFF,8'hFF,8'hFF,8'h00};
reg [7:0] port_dip[6]  = '{8'h80,8'h80,8'h80,8'h80,8'h80,8'h80};
wire [5:0] map_idx  = ioctl_addr[5:0] - 6'd16;
wire [2:0] idle_idx = ioctl_addr[2:0] - 3'd4;
wire [3:0] dip_idx4 = ioctl_addr[3:0] - 4'd10;
wire [2:0] dip_idx  = dip_idx4[2:0];

// index 5 = discrete sound programs, one 8 KB slot per dsnd_engine (address bits 14:13 = engine 0-3); a game-ID load
// mutes all four, each engine plays again once its slot is written
reg [3:0] ds_on = 4'd0;
always @(posedge CLK_SYS) if (ioctl_wr) begin
    if (ioctl_index == 8'd1 && ioctl_addr == 25'd0) ds_on <= 4'd0;
    if (ioctl_index == 8'd5) ds_on[ioctl_addr[14:13]] <= 1'b1;
end

always @(posedge CLK_SYS) begin
    if (ioctl_wr && ioctl_index == 8'd1) begin
        if (ioctl_addr == 25'd0) game_var    <= ioctl_dout;
        if (ioctl_addr == 25'd1) game_flags  <= ioctl_dout;
        if (ioctl_addr == 25'd2) core_byte   <= ioctl_dout;
        if (ioctl_addr == 25'd3) game_flags2 <= ioctl_dout;
        if (ioctl_addr >= 25'd4  && ioctl_addr < 25'd10) port_idle[idle_idx] <= ioctl_dout;
        if (ioctl_addr >= 25'd10 && ioctl_addr < 25'd16) port_dip[dip_idx]   <= ioctl_dout;
        if (ioctl_addr >= 25'd16 && ioctl_addr < 25'd64) in_map[map_idx] <= {ioctl_dout[7], ioctl_dout[5:0]};
    end
end

wire game_vert = game_flags[4];
wire [15:0] hs_address;
wire  [7:0] hs_data_in;
wire  [7:0] hs_data_out;
wire        hs_write_enable;
wire        hs_access_read;
wire        hs_access_write;
wire        hs_pause;
wire        hs_configured;
wire turned    = game_vert ^ status[12];

wire [1:0] ar = status[9:8];

wire        art_fb;
wire        art_wait, art_avail;
wire [11:0] art_cw, art_ch;
assign VIDEO_ARX = (!ar) ? (art_fb ? art_cw : turned ? 12'd3 : 12'd4) : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? (art_fb ? art_ch : turned ? 12'd4 : 12'd3) : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"SEGAVICDUAL;;",
	"P1,Video Options;",
	"P1O89,Aspect Ratio,Original,Full screen,[ARC1],[ARC2];",
	"H4P1OC,Orientation,Vert,Horz;",
	"H5P1OC,Orientation,Horz,Vert;",
	"P1OM,Flip Screen,Off,On;",
	"P1O[40:37],H Position (CRT),0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[44:41],V Position (CRT),0,+1,+2,+3,+4,+5,+6,+7,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1OGI,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"-;",
	"H1P2,Game Options;",
	"H3P2-,Artwork (MAME layout views);",
	"H3P2O[52:49],View,Off,View 1,View 2,View 3,View 4,View 5,View 6,View 7,View 8,View 9,View 10,View 11,View 12,View 13,View 14,View 15;",
	"H3P2O[53],Backdrop,On,Off;",
	"H3P2O[54],Overlay,On,Off;",
	"H3P2O[55],Bezel,On,Off;",
	"H3P2O[58],Control Panel,On,Off;",
	"H3P2O[56],Side Art,On,Off;",
	"H3P2O[57],Zoom to Screen,Off,On;",
	"H1-;",
	"P3,Pause Options;",
	"P3OJ,Pause when OSD is open,On,Off;",
	"P3OK,Dim video after 10s,On,Off;",
	"-;",
	"P4,High Score Options;",
	"P4OL,Autosave Hiscores,Off,On;",
	"-;",
	"DIP;",
	"-;",
	"R0,Reset;",
	"J1,Button 1,Button 2,Button 3,Button 4,Coin,Start 1P,Start 2P,Pause,Button 5,Button 6,Rack Test;",
	"jn,A,B,X,Y,Select,Start,R,L;",
	"V,v",`BUILD_DATE
};

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(CLK_SYS),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),
	.video_rotated(video_rotated),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask({game_vert, ~game_vert, ~art_avail, 1'b1, ~art_avail, direct_video}),

	.ioctl_download(ioctl_download),
	.ioctl_upload(ioctl_upload),
	.ioctl_upload_req(ioctl_upload_req),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr27),
	.ioctl_dout(ioctl_dout),
	.ioctl_din(ioctl_din),
	.ioctl_index(ioctl_index),
	.ioctl_wait(art_wait),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_r_analog_0(joystick_r_analog_0),
	.joystick_r_analog_1(joystick_r_analog_1),
	.ps2_key(ps2_key)
);

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(CLK_SYS),
	.locked(locked)
);

wire reset = RESET | status[0] | buttons[1] | ioctl_download | ~locked;

wire [12:0] kb;
/* verilator lint_off PINCONNECTEMPTY */
ctl_keyboard keyboard(.clk(CLK_SYS), .ps2_key(ps2_key), .pause(pause_cpu), .kb(kb), .kbx());
/* verilator lint_on PINCONNECTEMPTY */

wire [3:0] dir1_raw = {joystick_0[3] | kb[0], joystick_0[2] | kb[1], joystick_0[1] | kb[2], joystick_0[0] | kb[3]};
wire [3:0] dir2_raw = joystick_1[3:0];
wire [3:0] dir1, dir2;

ctl_joy4way joy4way_1(.clk(CLK_SYS), .en(game_flags[0]), .in(dir1_raw), .out(dir1));
ctl_joy4way joy4way_2(.clk(CLK_SYS), .en(game_flags[0]), .in(dir2_raw), .out(dir2));

wire m_pause = joystick_0[11] | kb[12];

wire coin1, coin2;
ctl_coin_impulse #(.PAUSE_MODE(1)) coin_imp1(.clk(CLK_SYS), .pause(pause_cpu), .vblank(vblank), .en(game_flags[2]),
                           .coin_raw(joystick_0[8] | kb[8]), .coin(coin1));
ctl_coin_impulse #(.PAUSE_MODE(1)) coin_imp2(.clk(CLK_SYS), .pause(pause_cpu), .vblank(vblank), .en(game_flags[2]),
                           .coin_raw(joystick_1[8] | kb[9]), .coin(coin2));

wire rack_btn = joystick_0[14] | joystick_1[14];
wire rack_tog;
ctl_toggle rack_toggle(.clk(CLK_SYS), .clear(ioctl_download), .btn(rack_btn), .pause(pause_cpu), .q(rack_tog));

wire [3:0] rstick0, rstick1;
ctl_stick_dirs #(.MODE(0), .THRESH(7'd48)) rstick_0(.stick(joystick_r_analog_0), .dir(rstick0));
ctl_stick_dirs #(.MODE(0), .THRESH(7'd48)) rstick_1(.stick(joystick_r_analog_1), .dir(rstick1));

wire [35:0] ctl36;
ctl_ids ids(.joy0(joystick_0), .joy1(joystick_1), .kb(kb), .dir1(dir1), .dir2(dir2),
            .coin1(coin1), .coin2(coin2), .coin3(1'b0), .ctl(ctl36));

// ids 50-57: latched copies of P1 / P2 buttons 1-4 (PORT_TOGGLE panel switches, gen_mra TOGGLE_IDS)
wire [7:0] tog_btn = {ctl36[16:13], ctl36[8:5]};
wire [7:0] tog_q;
genvar ti;
generate
	for (ti = 0; ti < 8; ti = ti + 1) begin : g_tog
		ctl_toggle btn_toggle(.clk(CLK_SYS), .clear(ioctl_download), .btn(tog_btn[ti]), .pause(pause_cpu), .q(tog_q[ti]));
	end
endgenerate

wire [63:0] ctl =
{
	6'd0,
	tog_q,
	joystick_1[5]  | rstick1[1],
	joystick_1[4]  | rstick1[0],
	joystick_0[5]  | rstick0[1],
	joystick_0[4]  | rstick0[0],
	joystick_1[13] | rstick1[3],
	joystick_1[12] | rstick1[2],
	joystick_1[7]  | rstick1[1],
	joystick_1[6]  | rstick1[0],
	joystick_0[13] | rstick0[3],
	joystick_0[12] | rstick0[2],
	joystick_0[7]  | rstick0[1],
	joystick_0[6]  | rstick0[0],
	rack_tog,
	rack_btn,
	ctl36
};

reg [7:0] dip_sw[8] = '{8'hFF,8'hFF,8'hFF,8'hFF,8'h00,8'h00,8'h00,8'h00};
always @(posedge CLK_SYS) begin
	if (ioctl_wr && (ioctl_index == 8'd254) && !ioctl_addr[24:3])
		dip_sw[ioctl_addr[2:0]] <= ioctl_dout;
end

wire [47:0]  port_idle_flat, port_sel_flat, in_ports;
wire  [7:0]  board_live;   // board live port lines (CBLANK, VBLANK, 64V, timer, coin status): DIP lines 8-15
wire [63:0]  dip_bytes_flat;
wire [383:0] in_map_flat;
genvar gi;
generate
	for (gi = 0; gi < 6; gi = gi + 1) begin : g_port
		assign port_idle_flat[gi*8 +: 8] = port_idle[gi];
		assign port_sel_flat[gi*8 +: 8]  = port_dip[gi];
	end
	for (gi = 0; gi < 8; gi = gi + 1) begin : g_dip
		assign dip_bytes_flat[gi*8 +: 8] = dip_sw[gi];
	end
	for (gi = 0; gi < 48; gi = gi + 1) begin : g_map
		assign in_map_flat[gi*8 +: 8] = {in_map[gi][6], 1'b0, in_map[gi][5:0]};
	end
endgenerate
// dips = port 5's DIP byte (dual-game SW1: IN0-IN3 SW1 bits read DIP lines 0x80 | n, gen_mra port_fixup) + the board's live
// lines (CUSTOM CBLANK / VBLANK / 64V / timer / coin status bits read 0x88 | n, gen_mra CUSTOM_LINES)
ctl_port_map #(.NP(6), .IDW(6), .DIP_MODE(1), .BASE_MODE(1)) port_map
(
	.clk(CLK_SYS), .idle(port_idle_flat), .in_map(in_map_flat), .dips({16'd0, board_live, dip_sw[port_dip[5][2:0]]}), .port_sel(port_sel_flat),
	.dip_bytes(dip_bytes_flat), .dip_bit(144'd0), .ctl(ctl), .ovr_mask(48'd0), .ovr_val(48'd0), .ports(in_ports)
);

wire [23:0] rgb_out;
pause #(8,8,8,31) pause   // CLKSPD = CLK_SYS MHz (30.93696)
(
	.*,
	.clk_sys(CLK_SYS),
	.user_button(m_pause),
	.pause_request(hs_pause),
	.options(~status[20:19])
);

wire hs, vs;
wire [7:0] r, g, b;
wire ce_pix;
wire        bd_hs, bd_vs, bd_hbl, bd_vbl;
wire  [7:0] bd_r, bd_g, bd_b;

wire        art_run, art_ddr;
wire [31:0] art_fb_base;
wire  [7:0] art_burstcnt, art_be;
wire [28:0] art_addr;
wire [63:0] art_din;
wire        art_rd, art_we, art_clk;
artwork #(.IDX(8'd6)) artwork
(
	.clk(CLK_SYS),
	.sel(status[52:49]), .layer_off({status[58], status[55:53]}), .side_off(status[56]), .zoom(status[57]),
	.crt_flip(status[22]), .hdmi_flip(1'b0), .turn(status[12]), .avail(art_avail),
	.hdmi_w(HDMI_WIDTH), .hdmi_h(HDMI_HEIGHT),
	.ioctl_download(ioctl_download), .ioctl_index(ioctl_index), .ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr27), .ioctl_dout(ioctl_dout), .ioctl_wait(art_wait),
	.ce_pix(ce_pix),
	.hs_in(bd_hs), .vs_in(bd_vs), .hblank_in(bd_hbl), .vblank_in(bd_vbl), .rgb_in({bd_r, bd_g, bd_b}),
	.hs_out(hs), .vs_out(vs), .hblank_out(hblank), .vblank_out(vblank), .rgb_out({r, g, b}),
	.running(art_run), .ddr_owner(art_ddr), .canvas_w(art_cw), .canvas_h(art_ch),
	.fb_base(art_fb_base), .fb_vbl(FB_VBL),
	.DDRAM_CLK(art_clk), .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(art_burstcnt), .DDRAM_ADDR(art_addr),
	.DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(art_rd),
	.DDRAM_DIN(art_din), .DDRAM_BE(art_be), .DDRAM_WE(art_we)
);
assign art_fb = art_run & ~direct_video;

wire rotate_ccw = ~game_flags[7];
wire no_rotate  = ~turned | direct_video;
wire flip       = 1'b0;
wire        sr_fb_en, sr_clk, sr_rd, sr_we;
wire  [4:0] sr_fb_format;
wire [11:0] sr_fb_w, sr_fb_h;
wire [31:0] sr_fb_base;
wire [13:0] sr_fb_stride;
wire  [7:0] sr_burstcnt, sr_be;
wire [28:0] sr_addr;
wire [63:0] sr_din;
screen_rotate screen_rotate
(
	.*,
	.FB_EN(sr_fb_en), .FB_FORMAT(sr_fb_format), .FB_WIDTH(sr_fb_w), .FB_HEIGHT(sr_fb_h),
	.FB_BASE(sr_fb_base), .FB_STRIDE(sr_fb_stride),
	.DDRAM_CLK(sr_clk), .DDRAM_BURSTCNT(sr_burstcnt), .DDRAM_ADDR(sr_addr), .DDRAM_DIN(sr_din),
	.DDRAM_BE(sr_be), .DDRAM_WE(sr_we), .DDRAM_RD(sr_rd)
);

assign FB_EN     = art_fb | sr_fb_en;
assign FB_FORMAT = art_fb ? 5'b00110  : sr_fb_format;
assign FB_WIDTH  = art_fb ? art_cw    : sr_fb_w;
assign FB_HEIGHT = art_fb ? art_ch    : sr_fb_h;
assign FB_BASE   = art_fb ? art_fb_base : sr_fb_base;
assign FB_STRIDE = art_fb ? 14'd8192  : sr_fb_stride;
assign DDRAM_CLK      = CLK_SYS;
assign DDRAM_BURSTCNT = art_ddr ? art_burstcnt : sr_burstcnt;
assign DDRAM_ADDR     = art_ddr ? art_addr : sr_addr;
assign DDRAM_DIN      = art_ddr ? art_din : sr_din;
assign DDRAM_BE       = art_ddr ? art_be : sr_be;
assign DDRAM_WE       = art_ddr ? art_we : sr_we;
assign DDRAM_RD       = art_ddr ? art_rd : sr_rd;

arcade_video #(256,24) arcade_video
(
	.*,

	.clk_video(CLK_SYS),

	.RGB_in(rgb_out),
	.HBlank(hblank),
	.VBlank(vblank),
	.HSync(hs),
	.VSync(vs),

	.fx(status[18:16])
);

segavicdual_dispatcher board
(
	.clk(CLK_SYS),
	.reset(reset),
	.pause(pause_cpu),
	.variant(game_var),
	.core_byte(core_byte),
	.game_flags2(game_flags2),
	.ce_pix(ce_pix),

	.in_ports(in_ports),
	.live(board_live),

	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wr0(ioctl_wr & (ioctl_index == 8'd0)),
	.ds_wr(ioctl_wr & (ioctl_index == 8'd5)), .ds_addr(ioctl_addr[14:0]), .ds_data(ioctl_dout), .ds_on(ds_on),

	.crt_flip(status[22]),
	.h_adj(status[40:37]),
	.v_adj(status[44:41]),

	.video_r(bd_r),
	.video_g(bd_g),
	.video_b(bd_b),
	.video_hs(bd_hs),
	.video_vs(bd_vs),
	.video_hblank(bd_hbl),
	.video_vblank(bd_vbl),

	.audio_l(audio_l),
	.audio_r(audio_r),

	.hs_address(hs_address),
	.hs_data_in(hs_data_in),
	.hs_data_out(hs_data_out),
	.hs_write(hs_write_enable)
);

hiscore #(
	.HS_ADDRESSWIDTH(16),
	.CFG_ADDRESSWIDTH(4),
	.CFG_LENGTHWIDTH(2)
) hi (
	.*,
	.clk(CLK_SYS),
	.paused(pause_cpu),
	.autosave(status[21]),
	.ram_address(hs_address),
	.data_from_ram(hs_data_out),
	.data_to_ram(hs_data_in),
	.data_from_hps(ioctl_dout),
	.data_to_hps(ioctl_din),
	.ram_write(hs_write_enable),
	.ram_intent_read(hs_access_read),
	.ram_intent_write(hs_access_write),
	.pause_cpu(hs_pause),
	.configured(hs_configured)
);

endmodule
