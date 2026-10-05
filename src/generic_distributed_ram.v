module generic_distributed_ram #(
    parameter DATA_WIDTH = 49,  // 데이터 비트 폭
    parameter DEPTH = 16   // 깊이 (16, 32, 64 권장 - LUT 크기에 최적화)
)(
    input clk,

    // Write Port (동기식 쓰기)
    input we,
    input [$clog2(DEPTH)-1:0] waddr,
    input [DATA_WIDTH-1:0] wdata,

    // Read Port (비동기식 분산 RAM 읽기)
    input [$clog2(DEPTH)-1:0] raddr,
    output [DATA_WIDTH-1:0] rdata
);

    // Xilinx 및 표준 툴에 Distributed RAM 강제 추론 지시어 부여
    (* ram_style = "distributed" *) logic [DATA_WIDTH-1:0] ram [DEPTH];

    // 1. Synchronous Write
    always_ff @(posedge clk) begin
        if (we) begin
            ram[waddr] <= wdata;
        end
    end

    // 2. Asynchronous Read (LUTRAM 특유의 0-cycle 읽기)
    assign rdata = ram[raddr];

endmodule