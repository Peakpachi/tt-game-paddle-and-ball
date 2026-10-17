`default_nettype none

module ip_debounce #(
    parameter N = 16
) (
    input  wire clk,
    input  wire rst_n,
    input  wire noisy,
    output reg  clean
);

    localparam COUNT_W = (N <= 1) ? 1 : $clog2(N);

    reg sync1, sync2;
    reg [COUNT_W-1:0] count;

    always @(posedge clk) begin
        if (!rst_n) begin
            sync1 <= 1'b0;
            sync2 <= 1'b0;
            count <= 0;
            clean <= 1'b0;
        end else begin
            sync1 <= noisy;
            sync2 <= sync1;

            if (sync2 == clean) begin
                count <= 0;
            end else if (count == N-1) begin
                clean <= sync2;
                count <= 0;
            end else begin
                count <= count + 1'b1;
            end
        end
    end

endmodule
