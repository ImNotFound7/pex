module tt_um_imnotfound7_pex (
    ena,
    rst_n,
    clk,
    ui_in,
    uio_in,
    uo_out,
    uio_out,
    uio_oe
);

    input ena;
    input rst_n;
    input clk;
    input [7:0] ui_in;
    input [7:0] uio_in;
    output [7:0] uo_out;
    output [7:0] uio_out;
    output [7:0] uio_oe;

    wire [7:0] _11;
    wire _4;
    wire _6;
    wire _14;
    wire _8;
    wire [7:0] _17;
    wire [7:0] _18;
    wire [7:0] _9;
    reg [7:0] _16;
    assign _11 = 8'b00000000;
    assign _4 = ena;
    assign _6 = rst_n;
    assign _14 = ~ _6;
    assign _8 = clk;
    assign _17 = 8'b00000001;
    assign _18 = _16 + _17;
    assign _9 = _18;
    always @(posedge _8) begin
        if (_14)
            _16 <= _11;
        else
            if (_4)
                _16 <= _9;
    end
    assign uo_out = _16;
    assign uio_out = _11;
    assign uio_oe = _11;

endmodule
