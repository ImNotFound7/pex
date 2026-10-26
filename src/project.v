module tt_um_imnotfound7_pex (
    rst_n,
    clk,
    ui_in,
    ena,
    uio_in,
    uo_out,
    uio_out,
    uio_oe
);

    input rst_n;
    input clk;
    input [7:0] ui_in;
    input ena;
    input [7:0] uio_in;
    output [7:0] uo_out;
    output [7:0] uio_out;
    output [7:0] uio_oe;

    wire [7:0] _13;
    wire [7:0] _49;
    wire [15:0] _44;
    wire gnd;
    wire [15:0] _40;
    wire [15:0] _39;
    wire [14:0] _37;
    wire [7:0] _38;
    wire [31:0] _17;
    wire _21;
    wire [30:0] _20;
    wire [31:0] _22;
    wire [31:0] _3;
    reg [31:0] load_word;
    wire _35;
    wire _33;
    wire [4:0] _29;
    wire [4:0] _24;
    wire _5;
    wire _16;
    wire [4:0] _26;
    wire [4:0] _27;
    wire [4:0] _6;
    reg [4:0] load_count;
    wire _30;
    wire _18;
    wire _31;
    reg word_ready;
    wire _36;
    wire vdd;
    wire _8;
    wire [15:0] _46;
    wire [15:0] _9;
    wire [7:0] _48;
    wire [7:0] _11;
    wire _47;
    wire [7:0] _50;
    assign _13 = 8'b00000000;
    assign _49 = _9[15:8];
    assign _44 = 16'b0000000000000000;
    assign gnd = 1'b0;
    assign _40 = 16'b1111111111111111;
    assign _39 = load_word[15:0];
    assign _37 = load_word[30:16];
    assign _38 = _37[7:0];
    assign _17 = 32'b00000000000000000000000000000000;
    assign _21 = _11[2:2];
    assign _20 = load_word[30:0];
    assign _22 = { _20,
                   _21 };
    assign _3 = _22;
    always @(posedge _8) begin
        if (_16)
            load_word <= _17;
        else
            if (_18)
                load_word <= _3;
    end
    assign _35 = load_word[31:31];
    assign _33 = 1'b0;
    assign _29 = 5'b11111;
    assign _24 = 5'b00000;
    assign _5 = rst_n;
    assign _16 = ~ _5;
    assign _26 = 5'b00001;
    assign _27 = load_count + _26;
    assign _6 = _27;
    always @(posedge _8) begin
        if (_16)
            load_count <= _24;
        else
            if (_18)
                load_count <= _6;
    end
    assign _30 = load_count == _29;
    assign _18 = _11[1:1];
    assign _31 = _18 & _30;
    always @(posedge _8) begin
        if (_16)
            word_ready <= _33;
        else
            word_ready <= _31;
    end
    assign _36 = word_ready & _35;
    assign vdd = 1'b1;
    assign _8 = clk;
    RM_IHPSG13_1P_256x16_c2_bm_bist
        sram
        ( .A_CLK(_8),
          .A_MEN(vdd),
          .A_WEN(_36),
          .A_REN(vdd),
          .A_ADDR(_38),
          .A_DIN(_39),
          .A_DLY(vdd),
          .A_BM(_40),
          .A_BIST_CLK(gnd),
          .A_BIST_EN(gnd),
          .A_BIST_MEN(gnd),
          .A_BIST_WEN(gnd),
          .A_BIST_REN(gnd),
          .A_BIST_ADDR(_13),
          .A_BIST_DIN(_44),
          .A_BIST_BM(_44),
          .A_DOUT(_46[15:0]) );
    assign _9 = _46;
    assign _48 = _9[7:0];
    assign _11 = ui_in;
    assign _47 = _11[3:3];
    assign _50 = _47 ? _49 : _48;
    assign uo_out = _50;
    assign uio_out = _13;
    assign uio_oe = _13;

endmodule
