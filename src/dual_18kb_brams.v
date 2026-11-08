module dual_18kb_brams #(
    //36kb짜리 BRAM 하나를 18kb짜리 RAM 2개로 쪼개서 각각 읽기포트, 쓰기포트 할당해서 포트를 4개로 쪼개서 사용할 수 있게 하는 모듈
    //기본적으로 36 * 512, 36 * 512 18kb RAM 2개로 구성됨.

    // 18kb RAM 데이터 폭: 32 (일반 데이터) 또는 36 (패리티 비트 포함)
    parameter integer DATA_WIDTH = 32, 
    // 18kb RAM 데이터 깊이: 512 (36비트 * 512 = 18Kb)
    parameter integer DATA_DEPTH = 512, 
    // 출력 레지스터 (0: 1-cycle 레이턴시, 1: 2-cycle 레이턴시 - BRAM 내장 FF 사용)
    parameter integer OUT_REG    = 1
)(
    input  wire                   clk,
    
    // ==========================================
    // RAM 0 (18Kb Block A) - Simple Dual Port
    // ==========================================
    input  wire                   we_0,
    input  wire [$clog2(DATA_DEPTH)-1:0] addr_w_0,
    input  wire [DATA_WIDTH-1:0]  din_0,
    
    input  wire                   re_0,
    input  wire [$clog2(DATA_DEPTH)-1:0] addr_r_0,
    output wire [DATA_WIDTH-1:0]  dout_0,

    // ==========================================
    // RAM 1 (18Kb Block B) - Simple Dual Port
    // ==========================================
    input  wire                   we_1,
    input  wire [$clog2(DATA_DEPTH)-1:0] addr_w_1,
    input  wire [DATA_WIDTH-1:0]  din_1,
    
    input  wire                   re_1,
    input  wire [$clog2(DATA_DEPTH)-1:0] addr_r_1,
    output wire [DATA_WIDTH-1:0]  dout_1
);

    // 합성기가 BRAM으로 인식하도록 속성 부여
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem_0 [0:DATA_DEPTH-1];
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem_1 [0:DATA_DEPTH-1];

    reg [DATA_WIDTH-1:0] ram_out_0 = 0;
    reg [DATA_WIDTH-1:0] ram_out_1 = 0;

    // -------------------------------------------------------------
    // RAM 0 로직 (Ping)
    // -------------------------------------------------------------
    always @(posedge clk) begin
        if (we_0) mem_0[addr_w_0] <= din_0;
        if (re_0) ram_out_0 <= mem_0[addr_r_0];
    end

    // -------------------------------------------------------------
    // RAM 1 로직 (Pong)
    // -------------------------------------------------------------
    always @(posedge clk) begin
        if (we_1) mem_1[addr_w_1] <= din_1;
        if (re_1) ram_out_1 <= mem_1[addr_r_1];
    end

    // -------------------------------------------------------------
    // 출력 파이프라인 (OUT_REG) 로직
    // -------------------------------------------------------------
    generate
        if (OUT_REG == 1) begin : gen_out_reg
            // BRAM 내장 출력 FF로 흡수됨 (2-cycle latency)
            reg [DATA_WIDTH-1:0] pipe_out_0 = 0;
            reg [DATA_WIDTH-1:0] pipe_out_1 = 0;

            always @(posedge clk) begin
                if (re_0) pipe_out_0 <= ram_out_0;
                if (re_1) pipe_out_1 <= ram_out_1;
            end
            
            assign dout_0 = pipe_out_0;
            assign dout_1 = pipe_out_1;
        end else begin : gen_no_out_reg
            // BRAM 기본 Latch 출력 (1-cycle latency)
            assign dout_0 = ram_out_0;
            assign dout_1 = ram_out_1;
        end
    endgenerate

endmodule