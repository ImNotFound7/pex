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

    wire [7:0] _12;
    wire [7:0] _46;
    wire _41;
    wire _39;
    wire [4:0] _35;
    wire [4:0] _16;
    wire [4:0] _19;
    wire [4:0] _20;
    wire [4:0] _3;
    reg [4:0] load_count;
    wire _36;
    wire _37;
    reg word_ready;
    wire _42;
    wire [15:0] _34;
    reg [15:0] imem_array[0:127];
    wire vdd;
    wire [6:0] _31;
    wire _17;
    wire [31:0] _22;
    wire _5;
    wire _15;
    wire _7;
    wire _25;
    wire [30:0] _24;
    wire [31:0] _26;
    wire [31:0] _8;
    reg [31:0] load_word;
    wire [14:0] _28;
    wire [6:0] _29;
    reg [6:0] imem_raddr;
    wire [15:0] imem_rdata;
    wire [7:0] _45;
    wire [7:0] _10;
    wire _27;
    wire [7:0] _47;
    assign _12 = 8'b00000000;
    assign _46 = imem_rdata[15:8];
    assign _41 = load_word[31:31];
    assign _39 = 1'b0;
    assign _35 = 5'b11111;
    assign _16 = 5'b00000;
    assign _19 = 5'b00001;
    assign _20 = load_count + _19;
    assign _3 = _20;
    always @(posedge _7) begin
        if (_15)
            load_count <= _16;
        else
            if (_17)
                load_count <= _3;
    end
    assign _36 = load_count == _35;
    assign _37 = _17 & _36;
    always @(posedge _7) begin
        if (_15)
            word_ready <= _39;
        else
            word_ready <= _37;
    end
    assign _42 = word_ready & _41;
    assign _34 = load_word[15:0];
    always @(posedge _7) begin
        if (_42)
            imem_array[_29] <= _34;
    end
    assign vdd = 1'b1;
    assign _31 = 7'b0000000;
    assign _17 = _10[1:1];
    assign _22 = 32'b00000000000000000000000000000000;
    assign _5 = rst_n;
    assign _15 = ~ _5;
    assign _7 = clk;
    assign _25 = _10[2:2];
    assign _24 = load_word[30:0];
    assign _26 = { _24,
                   _25 };
    assign _8 = _26;
    always @(posedge _7) begin
        if (_15)
            load_word <= _22;
        else
            if (_17)
                load_word <= _8;
    end
    assign _28 = load_word[30:16];
    assign _29 = _28[6:0];
    always @(posedge _7) begin
        imem_raddr <= _29;
    end
    assign imem_rdata = imem_array[imem_raddr];
    assign _45 = imem_rdata[7:0];
    assign _10 = ui_in;
    assign _27 = _10[3:3];
    assign _47 = _27 ? _46 : _45;
    assign uo_out = _47;
    assign uio_out = _12;
    assign uio_oe = _12;

endmodule
