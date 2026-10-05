module vtx_stream_fifo#( 
    parameter DEPTH = 16 //x, y, z의 비트수 합이 48이기 떄문에 49(last 1비트 추가) x DEPTH Distribute Ram을 선언하게 됨.
)(
    input clk,
    input reset,

    // 1. Producer Interface (상위 Packet Depacker 모듈에서 입력)
    input [15:0] p_vtx_x,
    input [15:0] p_vtx_y,
    input [15:0] p_vtx_z,
    input p_vtx_last,   // 서브메시 마지막 정점 플래그
    input p_vtx_valid,
    output reg p_vtx_ready, //사실 웬만하면 그냥 1로 고정해야 함. 스트리밍 방식이라 그냥 다 데이터 받아줘야 함.

    // 2. Consumer Interface (공정 2 DSP 파이프라인 - FWFT)
    output [15:0] c_vtx_x,
    output [15:0] c_vtx_y,
    output [15:0] c_vtx_z,
    output c_vtx_last,
    output c_vtx_valid,
    input c_vtx_ready,

    // 상태 플래그
    output reg fifo_empty,
    output reg fifo_almost_full
);
/*
//기본적으로 Zynq의 HP포트를 이용해서 DDR3에서 서브메쉬 데이터 패킷을 64비트씩 정확히 1KiB를 Burst로 읽어옴.
//서브메쉬 하나당 정점은 최대 63개, 삼각형은 최대 127개 저장이 가능함.
//맨 앞에는 128bit짜리 헤더가 있음. 이렇게 구성됨.
[63:56] : Reserved(사용되지 않음)
[55:48] : 해당 서브메쉬가 속한 오브젝트 ID(obj_id)
[47:40] : 해당 서브메쉬의 삼각형 개수(tri_coun, 최대 127개)
[39:32] : 해당 서브메쉬의 정점 개수(vtx_count, 최대 63개)
[31:0] : 해당 서브메쉬 Offset X(오브젝트의 원점에 대한 서브메쉬 원점의 위치)(SQ7.8)

[63:32] : 해당 서브메쉬 Offset Y(오브젝트의 원점에 대한 서브메쉬 원점의 위치)(SQ7.8)
[31:0] : 해당 서브메쉬 Offset Z(오브젝트의 원점에 대한 서브메쉬 원점의 위치)(SQ7.8)

//패킷은 하나당 128bit이며 이렇게 구성되어 있음. 이런게 총 63개 존재함.
[63:48] : 해당 정점 텍스쳐의 V (16 bit)(UQ0.16)
[47:32] : 해당 정점 텍스쳐의 U (16 bit)(UQ0.16)
[31:16] : 정점 좌표 Y (16 bit)(SQ1.14)
[15:0] : 정점 좌표 X (16 bit)(SQ1.14)

[63:56] : 삼각형 1의 정점 인덱스2
[55:48] : 삼각형 1의 정점 인덱스1
[47:40] : 삼각형 1의 정점 인덱스0
[39:32] : 삼각형 0의 정점 인덱스2
[31:24] : 삼각형 0의 정점 인덱스1
[23:16] : 삼각형 0의 정점 인덱스0
[15:0] : 정점 좌표 Z (16 bit)(SQ1.14)
*/
localparam int DATA_W = 49; //x(16b) + y(16b) + z(16b) + last(1b)
localparam int ADDR_W = $clog2(DEPTH);

wire [DATA_W-1:0] disram_w_data = {p_vtx_last, p_vtx_z[15:0], p_vtx_y[15:0], p_vtx_x[15:0]};
wire disram_w_ena = (p_vtx_valid && p_vtx_ready);
wire [DATA_W-1:0] disram_r_data;

generic_distributed_ram #( //Distributed Ram 사용
    .DATA_WIDTH(DATA_W), //49
    .DEPTH(DEPTH) //16
) distributed_ram (
    .clk(clk),
    .we(disram_w_ena), //동기식 쓰기
    .waddr(fifo_wptr_ff[ADDR_W-1:0]),
    .wdata(disram_w_data),
    .raddr(fifo_rptr_ff[ADDR_W-1:0]), //비동기식 읽기
    .rdata(disram_r_data)
);

// Skid buffer로 들어갈 내부 신호
wire skid_s_ready;
wire fifo_has_data = (fifo_rptr_ff[ADDR_W:0] != fifo_wptr_ff[ADDR_W:0]);
wire [DATA_W-1:0] skid_m_data;

skid_buffer #(
    .DATA_WIDTH(DATA_W) // 49
) out_skid (
    .clk     (clk),
    .reset   (reset),

    // Upstream: Distributed RAM 비동기 출력 직결
    .s_valid (fifo_has_data), //input
    .s_ready (skid_s_ready), //output
    .s_data  (disram_r_data), //input

    // Downstream: 외부 Consumer (DSP)로 완전 레지스터화되어 출력
    .m_valid (c_vtx_valid), //output
    .m_ready (c_vtx_ready), //input
    .m_data  (skid_m_data) //output
);

reg [ADDR_W:0] fifo_rptr_ff;
reg [ADDR_W:0] fifo_wptr_ff;

wire [ADDR_W:0] fifo_rptr_next_comb = (fifo_has_data && skid_s_ready) ? (fifo_rptr_ff + 1): fifo_rptr_ff; //skid버퍼에게 전송 완료시 rptr 증가시켜야 함.
wire [ADDR_W:0] fifo_wptr_next_comb = (p_vtx_valid && p_vtx_ready) ? (fifo_wptr_ff + 1): fifo_wptr_ff; //producer에게 수신 완료시 wprt 증가시켜야 함.

wire [ADDR_W:0] fifo_count = fifo_wptr_next_comb - fifo_rptr_next_comb;

assign c_vtx_x    = skid_m_data[15:0];
assign c_vtx_y    = skid_m_data[31:16];
assign c_vtx_z    = skid_m_data[47:32];
assign c_vtx_last = skid_m_data[48];


always @(posedge clk) begin
    if(reset) begin
        //output reg들 다 초기화.
        p_vtx_ready <= 1; //처음에 1로 초기화.
        fifo_empty <= 1; //처음에 1로 초기화.
        fifo_almost_full <= 0;

        fifo_rptr_ff <= 0;
        fifo_wptr_ff <= 0;
    end
    else begin
        fifo_rptr_ff <= fifo_rptr_next_comb;
        fifo_wptr_ff <= fifo_wptr_next_comb;

        fifo_empty <= (fifo_rptr_next_comb[ADDR_W:0] == fifo_wptr_next_comb[ADDR_W:0] ) && !c_vtx_valid; //skid 버퍼에 데이터가 있을수도 있으니 c_vtx_valid까지 확인함.
        fifo_almost_full <= (fifo_count >= (DEPTH - 2)); // DEPTH - 2 (14개 이상 차면 Almost Full)

        p_vtx_ready <= 1; //그냥 1로 유지함. 
    end
end

endmodule