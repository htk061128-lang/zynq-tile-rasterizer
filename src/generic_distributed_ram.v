module generic_distributed_ram #( //1w1r(쓰기포트 1개, 읽기포트 1개)여서 포트는 총 2개임.
    parameter DATA_WIDTH = 49,  // 데이터 비트 폭
    parameter DEPTH = 16   // 깊이 (16, 32, 64 권장 - LUT 크기에 최적화), 16이나 32이면 LUT을 DEPTH개만 사용함.
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
/*
* X = 데이터 비트 폭(Data Width)
* Zynq-7020 (Xilinx 7 Series) Distributed RAM(LUTRAM) 기준 LUT 사용량
+-----------------------+-------------------------------------------+---------+---------+---------+
| 메모리 구조 (포트 수) | 주소 핀 작동 방식                         | 깊이 16 | 깊이 32 | 깊이 64 |
+-----------------------+-------------------------------------------+---------+---------+---------+
| Single Port (1W / 1R) | 쓰기와 읽기가 1개의 주소(addr)를 공유     |   1X    |   1X    |   1X    |
| Dual Port (1W1R)      | 쓰기 주소 1개, 읽기 주소 1개 분리         |   1X    |   1X    |   2X    |
| Quad Port (1W3R)      | 쓰기 주소 1개, 읽기 주소 3개 분리         |   2X    |   2X    |   4X    |
+-----------------------+-------------------------------------------+---------+---------+---------+
*/

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