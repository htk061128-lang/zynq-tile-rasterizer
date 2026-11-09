module vtx_pingpong_buffer #(
    parameter CHANNEL_0_1_WIDTH = 32, //18kb 메모리 하나의 width와 depth임. 
    parameter CHANNEL_0_1_DEPTH = 512, //18kb 메모리 2개로 36kb BRAM 하나가 구성되므로 기본 크기는 36 * 512 = 18kb여야 함.
    parameter CHANNEL_2_WIDTH = 18, //Distributed Ram 하나의 width와 depth임. 총 2개 생성해서 ping, pong 용도로 사용할 예정임.
    parameter CHANNEL_2_DEPTH = 64
) (
    input clk,
    input reset,

    output reg bank_sel_0, //채널 0의 뱅크상태 출력, 0: Ping에 쓰기 / Pong에서 읽기, 1: Pong에 쓰기 / Ping에서 읽기, (reset시 0으로 초기화 됨)
    output reg bank_sel_1, //채널 1의 뱅크상태 출력, 0: Ping에 쓰기 / Pong에서 읽기, 1: Pong에 쓰기 / Ping에서 읽기, (reset시 0으로 초기화 됨)
    output reg bank_sel_2, //채널 2의 뱅크상태 출력, 0: Ping에 쓰기 / Pong에서 읽기, 1: Pong에 쓰기 / Ping에서 읽기, (reset시 0으로 초기화 됨)

    input write_done_0, //채널 0의 마지막 데이터를 쓸때 같이 1로 주면 bank가 전환 됨(1클럭 펄스). 
    input write_done_1, //채널 1의 마지막 데이터를 쓸때 같이 1로 주면 bank가 전환 됨(1클럭 펄스).
    input write_done_2, //채널 2의 마지막 데이터를 쓸때 같이 1로 주면 bank가 전환 됨(1클럭 펄스).

    output reg read_start_0, //채널 0의 Ping이나 Pong버퍼가 완성되었을때 1로 출력됨(1클럭 펄스). 사실상 write_done_0의 1클럭 지연 신호임.
    output reg read_start_1, //채널 1의 Ping이나 Pong버퍼가 완성되었을때 1로 출력됨(1클럭 펄스). 사실상 write_done_0의 1클럭 지연 신호임.
    output reg read_start_2, //채널 2의 Ping이나 Pong버퍼가 완성되었을때 1로 출력됨(1클럭 펄스). 사실상 write_done_0의 1클럭 지연 신호임.
    
    // Write 채널 -------------------------------------------------
    // Write Channel 0(BRAM)
    input we_w0,
    input [$clog2(CHANNEL_0_1_DEPTH)-2:0] addr_w0, //CHANNEL_0_1_DEPTH = 512이면 8비트가 할당되어서 0 ~ 255까지의 값을 가질 수 있고, 
    input [CHANNEL_0_1_WIDTH-1:0] din_w0, //bank_sel에 따라 알아서 Ping이나 Pong으로 할당됨. X, Y 저장용
    
    // Write Channel 1(BRAM)
    input we_w1,
    input [$clog2(CHANNEL_0_1_DEPTH)-2:0] addr_w1, //CHANNEL_0_1_DEPTH = 512일때  0 ~ 255
    input [CHANNEL_0_1_WIDTH-1:0] din_w1, //U, V 저장용

    // Write Channel 2(Distributed RAM)
    input we_w2, //쓰기포트 1개, 읽기포트 3개인 18 * 64 Distributed RAM 2개로 핑퐁버퍼가 구현됨.
    input [$clog2(CHANNEL_2_DEPTH)-1:0] addr_w2,
    input [CHANNEL_2_WIDTH-1:0] din_w2, //1/Z 저장용

    // Read 채널 ---------------------------------------------------
    // Read Channel 0(BRAM)
    input re_r0_port0,
    input [$clog2(CHANNEL_0_1_DEPTH)-2:0] addr_r0_port0, //CHANNEL_0_1_DEPTH = 512일때  0 ~ 255
    output [CHANNEL_0_1_WIDTH-1:0] dout_r0_port0, //X, Y 읽기용, 2클럭 뒤에 나옴.

    input re_r0_port1,
    input [$clog2(CHANNEL_0_1_DEPTH)-2:0] addr_r0_port1, 
    output [CHANNEL_0_1_WIDTH-1:0] dout_r0_port1, //X, Y 읽기용, 2클럭 뒤에 나옴.

    input re_r0_port2,
    input [$clog2(CHANNEL_0_1_DEPTH)-2:0] addr_r0_port2,
    output [CHANNEL_0_1_WIDTH-1:0] dout_r0_port2, //X, Y 읽기용, 2클럭 뒤에 나옴.
    
    // Read Channel 1(BRAM)
    input re_r1_port0,
    input [$clog2(CHANNEL_0_1_DEPTH)-2:0] addr_r1_port0, //CHANNEL_0_1_DEPTH = 512일때  0 ~ 255
    output [CHANNEL_0_1_WIDTH-1:0] dout_r1_port0, //U, V 읽기용, 2클럭 뒤에 나옴.

    input re_r1_port1,
    input [$clog2(CHANNEL_0_1_DEPTH)-2:0] addr_r1_port1, 
    output [CHANNEL_0_1_WIDTH-1:0] dout_r1_port1, //U, V 읽기용, 2클럭 뒤에 나옴.

    input re_r1_port2,
    input [$clog2(CHANNEL_0_1_DEPTH)-2:0] addr_r1_port2, 
    output [CHANNEL_0_1_WIDTH-1:0] dout_r1_port2, //U, V 읽기용, 2클럭 뒤에 나옴.

    // Read Channel 2(Distributed RAM)
    input re_r2_port0,
    input [$clog2(CHANNEL_2_DEPTH)-1:0] addr_r2_port0,
    output reg [CHANNEL_2_WIDTH-1:0] dout_r2_port0, //1/Z 읽기용, 1클럭 뒤에 나옴!!

    input re_r2_port1,
    input [$clog2(CHANNEL_2_DEPTH)-1:0] addr_r2_port1,
    output reg [CHANNEL_2_WIDTH-1:0] dout_r2_port1, //1/Z 읽기용, 1클럭 뒤에 나옴!!

    input re_r2_port2,
    input [$clog2(CHANNEL_2_DEPTH)-1:0] addr_r2_port2,
    output reg [CHANNEL_2_WIDTH-1:0] dout_r2_port2 //1/Z 읽기용, 1클럭 뒤에 나옴!!
);
/*
물리적 36Kb BRAM 타일 (RAMB36E1) 1개
▼ (하드웨어적으로 2개의 18Kb 블록으로 분리) ▼

 [블록 1] 18Kb BRAM (RAMB18E1) : 폭 32-bit x 깊이 512
 ┌────────────────────────┐
 │  Ping 영역 (주소 0 ~ 255)                      │
 │ -----------------------------------------------│
 │  Pong 영역 (주소 256 ~ 511)                    │
 └────────────────────────┘
   ▲ Write Port 0 (채널 0 쓰기 전용)           ▲ Read Port 0 (채널 0 읽기 전용)
   
=========================================================

 [블록 2] 18Kb BRAM (RAMB18E1) : 폭 32-bit x 깊이 512
 ┌────────────────────────┐
 │  Ping 영역 (주소 0 ~ 255)                      │
 │ -----------------------------------------------│
 │  Pong 영역 (주소 256 ~ 511)                    │
 └────────────────────────┘
   ▲ Write Port 1 (채널 1 쓰기 전용)           ▲ Read Port 1 (채널 1 읽기 전용)
*/

wire [CHANNEL_2_WIDTH-1:0] c2_ping_r_data0, c2_ping_r_data1, c2_ping_r_data2;
wire [CHANNEL_2_WIDTH-1:0] c2_pong_r_data0, c2_pong_r_data1, c2_pong_r_data2;
wire [CHANNEL_2_WIDTH-1:0] dout_r2_port0_comb = (bank_sel_2) ? c2_ping_r_data0 : c2_pong_r_data0; //bank_sel이 0이면 Pong에서 읽고, 1이면 Ping에서 읽음.
wire [CHANNEL_2_WIDTH-1:0] dout_r2_port1_comb = (bank_sel_2) ? c2_ping_r_data1 : c2_pong_r_data1; //bank_sel이 0이면 Pong에서 읽고, 1이면 Ping에서 읽음.
wire [CHANNEL_2_WIDTH-1:0] dout_r2_port2_comb = (bank_sel_2) ? c2_ping_r_data2 : c2_pong_r_data2; //bank_sel이 0이면 Pong에서 읽고, 1이면 Ping에서 읽음.

always @(posedge clk) begin
    if (reset) begin
        // Reset logic if needed
        dout_r2_port0 <= 0;
        dout_r2_port1 <= 0;
        dout_r2_port2 <= 0;

        read_start_0 <= 0;
        read_start_1 <= 0;
        read_start_2 <= 0;

        bank_sel_0 <= 0; //0: Ping에 쓰기 / Pong에서 읽기, 1: Pong에 쓰기 / Ping에서 읽기
        bank_sel_1 <= 0; //0: Ping에 쓰기 / Pong에서 읽기, 1: Pong에 쓰기 / Ping에서 읽기
        bank_sel_2 <= 0; //0: Ping에 쓰기 / Pong에서 읽기, 1: Pong에 쓰기 / Ping에서 읽기
    end else begin
        // Additional logic if needed
        dout_r2_port0 <= dout_r2_port0_comb;
        dout_r2_port1 <= dout_r2_port1_comb;
        dout_r2_port2 <= dout_r2_port2_comb;

        read_start_0 <= write_done_0;
        read_start_1 <= write_done_1;
        read_start_2 <= write_done_2;

        if(write_done_0) begin
            bank_sel_0 <= ~bank_sel_0;
        end
        if(write_done_1) begin
            bank_sel_1 <= ~bank_sel_1;
        end
        if(write_done_2) begin
            bank_sel_2 <= ~bank_sel_2;
        end
    end
end

generic_distributed_ram_1w3r #(
    .DATA_WIDTH (CHANNEL_2_WIDTH),
    .DEPTH      (CHANNEL_2_DEPTH)
) dist_ram_ping (
    .clk        (clk),
    .we         (we_w2 && !bank_sel_2), // Ping에 쓰기
    .waddr      (addr_w2),
    .wdata      (din_w2),
    .raddr0     (addr_r2_port0),
    .rdata0     (c2_ping_r_data0),
    .raddr1     (addr_r2_port1),
    .rdata1     (c2_ping_r_data1),
    .raddr2     (addr_r2_port2),
    .rdata2     (c2_ping_r_data2)
);

generic_distributed_ram_1w3r #(
    .DATA_WIDTH (CHANNEL_2_WIDTH),
    .DEPTH      (CHANNEL_2_DEPTH)
) dist_ram_pong (
    .clk        (clk),
    .we         (we_w2 && bank_sel_2), // Pong에 쓰기
    .waddr      (addr_w2),
    .wdata      (din_w2),
    .raddr0     (addr_r2_port0),
    .rdata0     (c2_pong_r_data0),
    .raddr1     (addr_r2_port1),
    .rdata1     (c2_pong_r_data1),
    .raddr2     (addr_r2_port2),
    .rdata2     (c2_pong_r_data2)
);

wire b1_ram0_we = we_w0;
wire [$clog2(CHANNEL_0_1_DEPTH)-1:0] b1_ram0_w_ad = (bank_sel_0) ? {1'b1, addr_w0}: {1'b0, addr_w0}; //bank_sel이 0이면 Ping에 쓰고, 1이면 Pong에 씀.
wire [CHANNEL_0_1_WIDTH-1:0] b1_ram0_w_data = din_w0;
wire b1_ram0_re = re_r0_port0;
wire [$clog2(CHANNEL_0_1_DEPTH)-1:0] b1_ram0_r_ad = (bank_sel_0) ? {1'b0, addr_r0_port0}: {1'b1, addr_r0_port0};  //bank_sel이 0이면 Pong에서 읽고, 1이면 Ping에서 읽음.
wire [CHANNEL_0_1_WIDTH-1:0] b1_ram0_r_data;

assign dout_r0_port0 = b1_ram0_r_data;

wire b1_ram1_we = we_w1;
wire [$clog2(CHANNEL_0_1_DEPTH)-1:0] b1_ram1_w_ad = (bank_sel_1) ? {1'b1, addr_w1}: {1'b0, addr_w1}; //bank_sel이 0이면 Ping에 쓰고, 1이면 Pong에 씀.
wire [CHANNEL_0_1_WIDTH-1:0] b1_ram1_w_data = din_w1;
wire b1_ram1_re = re_r1_port0;
wire [$clog2(CHANNEL_0_1_DEPTH)-1:0] b1_ram1_r_ad = (bank_sel_1) ? {1'b0, addr_r1_port0}: {1'b1, addr_r1_port0};  //bank_sel이 0이면 Pong에서 읽고, 1이면 Ping에서 읽음.
wire [CHANNEL_0_1_WIDTH-1:0] b1_ram1_r_data;

assign dout_r1_port0 = b1_ram1_r_data;

dual_18kb_brams #(
    .DATA_WIDTH (CHANNEL_0_1_WIDTH),  // 데이터 폭 (32 or 36)
    .DATA_DEPTH (CHANNEL_0_1_DEPTH), // 메모리 깊이 (512)
    .OUT_REG    (1)    // 출력 레지스터 (0: 1-cycle, 1: 2-cycle latency)
) bram1 (
    .clk        (clk), // 시스템 클럭
    .we_0       (b1_ram0_we),
    .addr_w_0   (b1_ram0_w_ad),
    .din_0      (b1_ram0_w_data),
    .re_0       (b1_ram0_re),
    .addr_r_0   (b1_ram0_r_ad),
    .dout_0     (b1_ram0_r_data),
    .we_1       (b1_ram1_we),
    .addr_w_1   (b1_ram1_w_ad),
    .din_1      (b1_ram1_w_data),
    .re_1       (b1_ram1_re),
    .addr_r_1   (b1_ram1_r_ad),
    .dout_1     (b1_ram1_r_data)
);

wire b2_ram0_we = we_w0;
wire [$clog2(CHANNEL_0_1_DEPTH)-1:0] b2_ram0_w_ad = (bank_sel_0) ? {1'b1, addr_w0}: {1'b0, addr_w0};
wire [CHANNEL_0_1_WIDTH-1:0] b2_ram0_w_data = din_w0;
wire b2_ram0_re = re_r0_port1;
wire [$clog2(CHANNEL_0_1_DEPTH)-1:0] b2_ram0_r_ad = (bank_sel_0) ? {1'b0, addr_r0_port1}: {1'b1, addr_r0_port1};
wire [CHANNEL_0_1_WIDTH-1:0] b2_ram0_r_data;

assign dout_r0_port1 = b2_ram0_r_data;

wire b2_ram1_we = we_w1;
wire [$clog2(CHANNEL_0_1_DEPTH)-1:0] b2_ram1_w_ad = (bank_sel_1) ? {1'b1, addr_w1}: {1'b0, addr_w1};
wire [CHANNEL_0_1_WIDTH-1:0] b2_ram1_w_data = din_w1;
wire b2_ram1_re = re_r1_port1;
wire [$clog2(CHANNEL_0_1_DEPTH)-1:0] b2_ram1_r_ad = (bank_sel_1) ? {1'b0, addr_r1_port1}: {1'b1, addr_r1_port1};
wire [CHANNEL_0_1_WIDTH-1:0] b2_ram1_r_data;

assign dout_r1_port1 = b2_ram1_r_data;

dual_18kb_brams #(
    .DATA_WIDTH (CHANNEL_0_1_WIDTH),
    .DATA_DEPTH (CHANNEL_0_1_DEPTH),
    .OUT_REG    (1)
) bram2 (
    .clk        (clk),
    .we_0       (b2_ram0_we),
    .addr_w_0   (b2_ram0_w_ad),
    .din_0      (b2_ram0_w_data),
    .re_0       (b2_ram0_re),
    .addr_r_0   (b2_ram0_r_ad),
    .dout_0     (b2_ram0_r_data),
    .we_1       (b2_ram1_we),
    .addr_w_1   (b2_ram1_w_ad),
    .din_1      (b2_ram1_w_data),
    .re_1       (b2_ram1_re),
    .addr_r_1   (b2_ram1_r_ad),
    .dout_1     (b2_ram1_r_data)
);

wire b3_ram0_we = we_w0;
wire [$clog2(CHANNEL_0_1_DEPTH)-1:0] b3_ram0_w_ad = (bank_sel_0) ? {1'b1, addr_w0}: {1'b0, addr_w0};
wire [CHANNEL_0_1_WIDTH-1:0] b3_ram0_w_data = din_w0;
wire b3_ram0_re = re_r0_port2;
wire [$clog2(CHANNEL_0_1_DEPTH)-1:0] b3_ram0_r_ad = (bank_sel_0) ? {1'b0, addr_r0_port2}: {1'b1, addr_r0_port2};
wire [CHANNEL_0_1_WIDTH-1:0] b3_ram0_r_data;

assign dout_r0_port2 = b3_ram0_r_data;

wire b3_ram1_we = we_w1;
wire [$clog2(CHANNEL_0_1_DEPTH)-1:0] b3_ram1_w_ad = (bank_sel_1) ? {1'b1, addr_w1}: {1'b0, addr_w1};
wire [CHANNEL_0_1_WIDTH-1:0] b3_ram1_w_data = din_w1;
wire b3_ram1_re = re_r1_port2;
wire [$clog2(CHANNEL_0_1_DEPTH)-1:0] b3_ram1_r_ad = (bank_sel_1) ? {1'b0, addr_r1_port2}: {1'b1, addr_r1_port2};
wire [CHANNEL_0_1_WIDTH-1:0] b3_ram1_r_data;

assign dout_r1_port2 = b3_ram1_r_data;

dual_18kb_brams #(
    .DATA_WIDTH (CHANNEL_0_1_WIDTH),
    .DATA_DEPTH (CHANNEL_0_1_DEPTH),
    .OUT_REG    (1)
) bram3 (
    .clk        (clk),
    .we_0       (b3_ram0_we),
    .addr_w_0   (b3_ram0_w_ad),
    .din_0      (b3_ram0_w_data),
    .re_0       (b3_ram0_re),
    .addr_r_0   (b3_ram0_r_ad),
    .dout_0     (b3_ram0_r_data),
    .we_1       (b3_ram1_we),
    .addr_w_1   (b3_ram1_w_ad),
    .din_1      (b3_ram1_w_data),
    .re_1       (b3_ram1_re),
    .addr_r_1   (b3_ram1_r_ad),
    .dout_1     (b3_ram1_r_data)
);

endmodule