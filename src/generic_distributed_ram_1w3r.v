module generic_distributed_ram_1w3r #(
    parameter DATA_WIDTH = 49,
    parameter DEPTH = 16 
)(
    input clk,

    // Write Port (동기식 쓰기)
    input we,
    input [$clog2(DEPTH)-1:0] waddr,
    input [DATA_WIDTH-1:0] wdata,

    // Read Port 0 (독립 읽기 1)
    input [$clog2(DEPTH)-1:0] raddr0,
    output [DATA_WIDTH-1:0] rdata0,

    // Read Port 1 (독립 읽기 2)
    input [$clog2(DEPTH)-1:0] raddr1,
    output [DATA_WIDTH-1:0] rdata1,

    // Read Port 2 (독립 읽기 3)
    input [$clog2(DEPTH)-1:0] raddr2,
    output [DATA_WIDTH-1:0] rdata2
);

    // Xilinx 및 표준 툴에 Distributed RAM 강제 추론 지시어 부여
    (* ram_style = "distributed" *) logic [DATA_WIDTH-1:0] ram [DEPTH];

    // 1. Synchronous Write
    always_ff @(posedge clk) begin
        if (we) begin
            ram[waddr] <= wdata;
        end
    end

    // 2. Asynchronous Read (LUTRAM 특유의 0-cycle 읽기, 3포트 독립)
    assign rdata0 = ram[raddr0];
    assign rdata1 = ram[raddr1];
    assign rdata2 = ram[raddr2];

endmodule