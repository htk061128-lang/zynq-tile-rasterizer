module polygon_index_pingpong_buffer #(
    parameter BUFFER_WIDTH = 48, //48 * 64이고 WIDTH가 48이므로 한번에 2개 삼각형의 인덱스를 꺼내게 됨.
    parameter BUFFER_DEPTH = 64 //Distributed Ram 하나의 WIDTH와 DEPTH임. 이 모듈에서 Ping, Pong 용도로 2개를 사용함.
) (
    input clk,
    input reset,

    input write_done, //채널의 마지막 데이터를 쓸때 같이 1로 주면 bank가 전환 됨(1클럭 펄스). 
    output reg  read_start, //채널의 Ping이나 Pong버퍼가 완성되었을때 1로 출력됨(1클럭 펄스). 사실상 write_done의 1클럭 지연 신호임.

    output reg bank_sel, //채널의 뱅크상태 출력, 0: Ping에 쓰기 / Pong에서 읽기, 1: Pong에 쓰기 / Ping에서 읽기, (reset시 0으로 초기화 됨)

    //Write Channel ------------------------------------
    input we_w, //쓰기포트 1개, 읽기포트 3개인 18 * 64 Distributed RAM 2개로 핑퐁버퍼가 구현됨.
    input [$clog2(BUFFER_DEPTH)-1:0] addr_w,
    input [BUFFER_WIDTH-1:0] din_w, //삼각형 하나당 24비트의 인덱스를 가지고(정점당 8비트) 한줄에 총 2개의 삼각형 인덱스를 저장함(48비트)

    //Read Channel  -------------------------------------
    input re_r,
    input [$clog2(BUFFER_DEPTH)-1:0] addr_r,
    output reg [BUFFER_WIDTH-1:0] dout_r //1/Z 읽기용, 1클럭 뒤에 나옴!!
);
wire ram0_we = (bank_sel) ? 1'b0 : we_w; //ram0_we가 1이면 Ping에 쓰기, 0이면 Ping을 읽기
wire [$clog2(BUFFER_DEPTH)-1:0] ram0_addr = (bank_sel) ? addr_r : addr_w;
wire [BUFFER_WIDTH-1:0] ram0_wdata = din_w;
wire [BUFFER_WIDTH-1:0] ram0_rdata;

wire ram1_we = (bank_sel) ? we_w :1'b0; //ram1_we가 1이면 Pong에 쓰기, 0이면 Pong을 읽기
wire [$clog2(BUFFER_DEPTH)-1:0] ram1_addr = (bank_sel) ? addr_w : addr_r;
wire [BUFFER_WIDTH-1:0] ram1_wdata = din_w;
wire [BUFFER_WIDTH-1:0] ram1_rdata;

wire [BUFFER_WIDTH-1:0] dout_r_comb = (bank_sel) ? ram0_rdata: ram1_rdata; //bank_sel이 0: Ping에 쓰기 / Pong에서 읽기, 1: Pong에 쓰기 / Ping에서 읽기

always @(posedge clk) begin
    if(reset) begin
        dout_r <= 0;
        bank_sel <= 0;
        read_start <= 0;
    end
    else begin
        dout_r <= dout_r_comb;
        read_start <= write_done;
        if(write_done) begin
            bank_sel <= ~bank_sel;
        end
    end
end

generic_distributed_ram_single_port #( //Ping 버퍼
    .DATA_WIDTH (BUFFER_WIDTH), // 데이터 비트 폭 지정
    .DEPTH      (BUFFER_DEPTH)  // 메모리 깊이 지정
) u_single_port_ram0 (
    .clk        (clk),       // 시스템 클럭
    .we         (ram0_we),    // Write Enable (1일 때 addr 위치에 쓰기)
    .addr       (ram0_addr),  // 읽기/쓰기 공용 주소
    .wdata      (ram0_wdata), // 쓸 데이터
    .rdata      (ram0_rdata)  // 현재 addr 위치의 데이터 출력 (비동기 읽기)
);

generic_distributed_ram_single_port #( //Pong 버퍼
    .DATA_WIDTH (BUFFER_WIDTH), // 데이터 비트 폭 지정
    .DEPTH      (BUFFER_DEPTH)  // 메모리 깊이 지정
) u_single_port_ram1 (
    .clk        (clk),       // 시스템 클럭
    .we         (ram1_we),    // Write Enable (1일 때 addr 위치에 쓰기)
    .addr       (ram1_addr),  // 읽기/쓰기 공용 주소
    .wdata      (ram1_wdata), // 쓸 데이터
    .rdata      (ram1_rdata)  // 현재 addr 위치의 데이터 출력 (비동기 읽기)
);

endmodule