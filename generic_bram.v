module generic_bram #(
    parameter integer TOTAL_BITS  = 32768,      // 4KB = 32768 bits
    parameter integer DATA_WIDTH  = 18,         // 8, 16, 18, 32, 36, 64, 72 등
    parameter integer BYTE_WIDTH  = 9,          // 바이트 분할 단위: 8, 9, 또는 DATA_WIDTH
    parameter         RAM_MODE    = "TRUE_DUAL",// "TRUE_DUAL" or "SIMPLE_DUAL"
    parameter         WRITE_MODE  = "NO_CHANGE",// "NO_CHANGE" (권장/저전력) or "READ_FIRST"
    parameter integer REG_OUT_A   = 0,          // Port A 출력 레지스터 (0: 1-cycle, 1: 2-cycle latency)
    parameter integer REG_OUT_B   = 0,          // Port B 출력 레지스터 (0: 1-cycle, 1: 2-cycle latency)
    parameter         INIT_FILE   = "",         // 초기화 헥스 파일 ($readmemh)

    // 파생 파라미터 자동 계산
    localparam integer WE_WIDTH   = (DATA_WIDTH + BYTE_WIDTH - 1) / BYTE_WIDTH,
    localparam integer DEPTH      = TOTAL_BITS / DATA_WIDTH,
    localparam integer ADDR_BITS  = $clog2(DEPTH)
)(
    // ==========================================
    // Port A (RAM_MODE="SIMPLE_DUAL"일 때 Write Only)
    // ==========================================
    input  wire                  clk_a,
    input  wire                  en_a,
    input  wire                  regce_a,
    input  wire                  rst_a,
    input  wire [WE_WIDTH-1:0]   we_a,
    input  wire [ADDR_BITS-1:0]  addr_a,
    input  wire [DATA_WIDTH-1:0] din_a,
    output wire [DATA_WIDTH-1:0] dout_a,

    // ==========================================
    // Port B (RAM_MODE="SIMPLE_DUAL"일 때 Read Only)
    // ==========================================
    input  wire                  clk_b,
    input  wire                  en_b,
    input  wire                  regce_b,
    input  wire                  rst_b,
    input  wire [WE_WIDTH-1:0]   we_b,
    input  wire [ADDR_BITS-1:0]  addr_b,
    input  wire [DATA_WIDTH-1:0] din_b,
    output wire [DATA_WIDTH-1:0] dout_b
);

    // BRAM 배열
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // 내부 읽기 데이터 레지스터 (BRAM Primitive Latch)
    reg [DATA_WIDTH-1:0] ram_data_a;
    reg [DATA_WIDTH-1:0] ram_data_b;

    // 출력 파이프라인 레지스터 (BRAM Primitive Optional Register)
    reg [DATA_WIDTH-1:0] pipe_reg_a;
    reg [DATA_WIDTH-1:0] pipe_reg_b;

    // -------------------------------------------------------------
    // 초기화 (Verilator 2-state 및 FPGA 비트스트림 초기값 대응)
    // -------------------------------------------------------------
    integer init_idx;
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end else begin
            for (init_idx = 0; init_idx < DEPTH; init_idx = init_idx + 1) begin
                mem[init_idx] = {DATA_WIDTH{1'b0}};
            end
        end
        ram_data_a = {DATA_WIDTH{1'b0}};
        ram_data_b = {DATA_WIDTH{1'b0}};
        pipe_reg_a = {DATA_WIDTH{1'b0}};
        pipe_reg_b = {DATA_WIDTH{1'b0}};
    end

    // -------------------------------------------------------------
    // Port A 처리 로직
    // -------------------------------------------------------------
    genvar i_a;
    generate
        // [1] 쓰기 제어 (Byte-wide Write Enable)
        for (i_a = 0; i_a < WE_WIDTH; i_a = i_a + 1) begin : gen_wr_a
            localparam integer L = i_a * BYTE_WIDTH;
            localparam integer H = ((L + BYTE_WIDTH) > DATA_WIDTH) ? (DATA_WIDTH - 1) : (L + BYTE_WIDTH - 1);

            always @(posedge clk_a) begin
                if (en_a && we_a[i_a]) begin
                    mem[addr_a][H:L] <= din_a[H:L];
                end
            end
        end

        // [2] 읽기 제어 (Xilinx/Intel BRAM 공식 템플릿 구조)
        if (RAM_MODE == "TRUE_DUAL") begin : gen_rd_a
            if (WRITE_MODE == "READ_FIRST") begin : gen_rf_a
                always @(posedge clk_a) begin
                    if (en_a) begin
                        ram_data_a <= mem[addr_a];
                    end
                end
            end else begin : gen_nc_a // NO_CHANGE (기본 권장값)
                always @(posedge clk_a) begin
                    if (en_a && (|we_a == 1'b0)) begin
                        ram_data_a <= mem[addr_a];
                    end
                end
            end
        end else begin : gen_sdp_dummy_a
            always @(*) begin
                ram_data_a = {DATA_WIDTH{1'b0}};
            end
        end

        // [3] 출력 파이프라인 레지스터 (BRAM 내장 FF로 흡수됨)
        if (REG_OUT_A == 1) begin : gen_pipe_a
            always @(posedge clk_a) begin
                if (rst_a) begin
                    pipe_reg_a <= {DATA_WIDTH{1'b0}};
                end else if (regce_a) begin
                    pipe_reg_a <= ram_data_a;
                end
            end
            assign dout_a = pipe_reg_a;
        end else begin : gen_wire_a
            assign dout_a = ram_data_a;
        end
    endgenerate

    // -------------------------------------------------------------
    // Port B 처리 로직
    // -------------------------------------------------------------
    genvar i_b;
    generate
        // [1] 쓰기 제어 (TRUE_DUAL일 때만)
        if (RAM_MODE == "TRUE_DUAL") begin : gen_wr_b
            for (i_b = 0; i_b < WE_WIDTH; i_b = i_b + 1) begin : gen_wr_slice_b
                localparam integer L = i_b * BYTE_WIDTH;
                localparam integer H = ((L + BYTE_WIDTH) > DATA_WIDTH) ? (DATA_WIDTH - 1) : (L + BYTE_WIDTH - 1);

                always @(posedge clk_b) begin
                    if (en_b && we_b[i_b]) begin
                        mem[addr_b][H:L] <= din_b[H:L];
                    end
                end
            end
        end

        // [2] 읽기 제어
        if (RAM_MODE == "TRUE_DUAL") begin : gen_rd_b
            if (WRITE_MODE == "READ_FIRST") begin : gen_rf_b
                always @(posedge clk_b) begin
                    if (en_b) begin
                        ram_data_b <= mem[addr_b];
                    end
                end
            end else begin : gen_nc_b // NO_CHANGE
                always @(posedge clk_b) begin
                    if (en_b && (|we_b == 1'b0)) begin
                        ram_data_b <= mem[addr_b];
                    end
                end
            end
        end else begin : gen_rd_sdp_b // SIMPLE_DUAL 모드 (Port B는 순수 읽기 전용)
            always @(posedge clk_b) begin
                if (en_b) begin
                    ram_data_b <= mem[addr_b];
                end
            end
        end

        // [3] 출력 파이프라인 레지스터 (BRAM 내장 FF로 흡수됨)
        if (REG_OUT_B == 1) begin : gen_pipe_b
            always @(posedge clk_b) begin
                if (rst_b) begin
                    pipe_reg_b <= {DATA_WIDTH{1'b0}};
                end else if (regce_b) begin
                    pipe_reg_b <= ram_data_b;
                end
            end
            assign dout_b = pipe_reg_b;
        end else begin : gen_wire_b
            assign dout_b = ram_data_b;
        end
    endgenerate

endmodule
