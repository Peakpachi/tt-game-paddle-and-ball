`default_nettype none

module ip_rect (
    input  wire [9:0] x,
    input  wire [9:0] y,
    input  wire [9:0] rx,
    input  wire [9:0] ry,
    input  wire [9:0] rw,
    input  wire [9:0] rh,
    output wire       hit
);
    wire [10:0] dx = {1'b0, x} - {1'b0, rx};
    wire [10:0] dy = {1'b0, y} - {1'b0, ry};

    assign hit = (x >= rx) && (y >= ry) &&
                 ({1'b0, dx} < {1'b0, rw}) &&
                 ({1'b0, dy} < {1'b0, rh});
endmodule
