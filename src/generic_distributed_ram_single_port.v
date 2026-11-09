module generic_distributed_ram_single_port #(
    parameter DATA_WIDTH = 48,  // 데이터 비트 폭
    parameter DEPTH = 64        // 깊이 (16, 32, 64 권장 - LUT 크기에 최적화)
)(
    input clk,
    
    input we,                               // Write Enable
    input [$clog2(DEPTH)-1:0] addr,         // 쓰기/읽기 공용 주소 포트 (Single Port 핵심)
    input [DATA_WIDTH-1:0] wdata,           // 쓰기 데이터
    
    output [DATA_WIDTH-1:0] rdata           // 비동기 읽기 데이터
);
/*
* X = 데이터 비트 폭(Data Width)
* Zynq-7020 (Xilinx 7 Series) Distributed RAM(LUTRAM) 기준
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

    // Synchronous Write
    always_ff @(posedge clk) begin
        if (we) begin
            ram[addr] <= wdata;
        end
    end

    // Asynchronous Read (LUTRAM 특유의 0-cycle 읽기)
    // we가 0일 때는 해당 addr의 데이터를 읽고, 
    // we가 1일 때는 쓰기가 진행중인 동일한 addr의 데이터를 읽게 됨(Write-First 또는 Read-First 특성은 합성기에 따라 다름)
    assign rdata = ram[addr];

endmodule