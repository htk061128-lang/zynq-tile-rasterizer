module generic_bram #(
    parameter integer TOTAL_BITS  = 32768,      // 총 용량 (32768 bits = 4KB)
    parameter integer DATA_WIDTH  = 18,         // 8, 16, 18, 32, 36, 64, 72 등
    parameter integer BYTE_WIDTH  = 9,          // 바이트 분할 단위 (8, 9, 또는 DATA_WIDTH)
    parameter         RAM_MODE    = "TRUE_DUAL",// "TRUE_DUAL" or "SIMPLE_DUAL"
    parameter         WRITE_MODE  = "NO_CHANGE",// "NO_CHANGE", "READ_FIRST", "WRITE_FIRST"
    parameter integer REG_OUT_A   = 0,          // Port A 출력 레지스터 (0: Latency 1, 1: Latency 2)
    parameter integer REG_OUT_B   = 0,          // Port B 출력 레지스터 (0: Latency 1, 1: Latency 2)
    parameter         INIT_FILE   = "",         // 초기화 헥스 파일 ($readmemh)

    // 파생 파라미터 자동 계산
    localparam integer WE_WIDTH   = (DATA_WIDTH + BYTE_WIDTH - 1) / BYTE_WIDTH,
    localparam integer DEPTH      = TOTAL_BITS / DATA_WIDTH,
    localparam integer ADDR_BITS  = $clog2(DEPTH)
)(
    // ==========================================
    // Port A (RAM_MODE="SIMPLE_DUAL"일 때는 Write Only)
    // ==========================================
    input  wire                  clk_a,
    input  wire                  en_a,
    input  wire                  regce_a,  // 출력 레지스터 클럭 인에이블 (REG_OUT_A=1일 때 사용)
    input  wire                  rst_a,    // 출력 레지스터 동기 리셋 (REG_OUT_A=1일 때 사용)
    input  wire [WE_WIDTH-1:0]   we_a,
    input  wire [ADDR_BITS-1:0]  addr_a,
    input  wire [DATA_WIDTH-1:0] din_a,
    output wire [DATA_WIDTH-1:0] dout_a,

    // ==========================================
    // Port B (RAM_MODE="SIMPLE_DUAL"일 때는 Read Only)
    // ==========================================
    input  wire                  clk_b,
    input  wire                  en_b,
    input  wire                  regce_b,  // 출력 레지스터 클럭 인에이블 (REG_OUT_B=1일 때 사용)
    input  wire                  rst_b,    // 출력 레지스터 동기 리셋 (REG_OUT_B=1일 때 사용)
    input  wire [WE_WIDTH-1:0]   we_b,     // SIMPLE_DUAL일 때는 무시됨
    input  wire [ADDR_BITS-1:0]  addr_b,
    input  wire [DATA_WIDTH-1:0] din_b,    // SIMPLE_DUAL일 때는 무시됨
    output wire [DATA_WIDTH-1:0] dout_b
);

    // BRAM 기본 메모리 배열
    (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // 메모리 어레이 내부 코어 출력 신호
    reg [DATA_WIDTH-1:0] ram_data_a;
    reg [DATA_WIDTH-1:0] ram_data_b;

    // 최종 등록용 파이프라인 레지스터
    reg [DATA_WIDTH-1:0] dout_a_reg;
    reg [DATA_WIDTH-1:0] dout_b_reg;

    // -------------------------------------------------------------
    // 초기화 ($readmemh or 0)
    // -------------------------------------------------------------
    integer i;
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end else begin
            for (i = 0; i < DEPTH; i = i + 1) begin
                mem[i] = {DATA_WIDTH{1'b0}};
            end
        end
        ram_data_a = {DATA_WIDTH{1'b0}};
        ram_data_b = {DATA_WIDTH{1'b0}};
        dout_a_reg = {DATA_WIDTH{1'b0}};
        dout_b_reg = {DATA_WIDTH{1'b0}};
    end

    // -------------------------------------------------------------
    // Port A: 메모리 코어 로직
    // -------------------------------------------------------------
    genvar a_i;
    generate
        // 쓰기 제어
        for (a_i = 0; a_i < WE_WIDTH; a_i = a_i + 1) begin : gen_wr_a
            localparam integer LOW  = a_i * BYTE_WIDTH;
            localparam integer HIGH = ((LOW + BYTE_WIDTH) > DATA_WIDTH) ? (DATA_WIDTH - 1) : (LOW + BYTE_WIDTH - 1);
            always @(posedge clk_a) begin
                if (en_a && we_a[a_i]) begin
                    mem[addr_a][HIGH:LOW] <= din_a[HIGH:LOW];
                end
            end
        end

        // 읽기 제어
        if (RAM_MODE == "TRUE_DUAL") begin : gen_porta_read
            if (WRITE_MODE == "READ_FIRST") begin : gen_rf_a
                always @(posedge clk_a) begin
                    if (en_a) ram_data_a <= mem[addr_a];
                end
            end else if (WRITE_MODE == "NO_CHANGE") begin : gen_nc_a
                always @(posedge clk_a) begin
                    if (en_a) begin
                        if (|we_a == 1'b0) ram_data_a <= mem[addr_a];
                    end
                end
            end else begin : gen_wf_a // WRITE_FIRST
                always @(posedge clk_a) begin
                    if (en_a) ram_data_a <= mem[addr_a];
                end
                for (a_i = 0; a_i < WE_WIDTH; a_i = a_i + 1) begin : gen_porta_wf_bypass
                    localparam integer LOW  = a_i * BYTE_WIDTH;
                    localparam integer HIGH = ((LOW + BYTE_WIDTH) > DATA_WIDTH) ? (DATA_WIDTH - 1) : (LOW + BYTE_WIDTH - 1);
                    always @(posedge clk_a) begin
                        if (en_a && we_a[a_i]) ram_data_a[HIGH:LOW] <= din_a[HIGH:LOW];
                    end
                end
            end
        end else begin : gen_porta_sdp_dummy
            always @(*) ram_data_a = {DATA_WIDTH{1'b0}};
        end

        // Port A 내장 출력 레지스터 (Synthesis tool이 BRAM 내부의 DOUT Register로 자동 흡수)
        if (REG_OUT_A == 1) begin : gen_reg_out_a
            always @(posedge clk_a) begin
                if (rst_a) begin
                    dout_a_reg <= {DATA_WIDTH{1'b0}};
                end else if (regce_a) begin
                    dout_a_reg <= ram_data_a;
                end
            end
            assign dout_a = dout_a_reg;
        end else begin : gen_no_reg_out_a
            assign dout_a = ram_data_a;
        end
    endgenerate

    // -------------------------------------------------------------
    // Port B: 메모리 코어 로직
    // -------------------------------------------------------------
    genvar b_i;
    generate
        if (RAM_MODE == "TRUE_DUAL") begin : gen_portb_tdp
            // Port B 쓰기
            for (b_i = 0; b_i < WE_WIDTH; b_i = b_i + 1) begin : gen_wr_b
                localparam integer LOW  = b_i * BYTE_WIDTH;
                localparam integer HIGH = ((LOW + BYTE_WIDTH) > DATA_WIDTH) ? (DATA_WIDTH - 1) : (LOW + BYTE_WIDTH - 1);
                always @(posedge clk_b) begin
                    if (en_b && we_b[b_i]) begin
                        mem[addr_b][HIGH:LOW] <= din_b[HIGH:LOW];
                    end
                end
            end

            // Port B 읽기
            if (WRITE_MODE == "READ_FIRST") begin : gen_rf_b
                always @(posedge clk_b) begin
                    if (en_b) ram_data_b <= mem[addr_b];
                end
            end else if (WRITE_MODE == "NO_CHANGE") begin : gen_nc_b
                always @(posedge clk_b) begin
                    if (en_b) begin
                        if (|we_b == 1'b0) ram_data_b <= mem[addr_b];
                    end
                end
            end else begin : gen_wf_b // WRITE_FIRST
                always @(posedge clk_b) begin
                    if (en_b) ram_data_b <= mem[addr_b];
                end
                for (b_i = 0; b_i < WE_WIDTH; b_i = b_i + 1) begin : gen_portb_wf_bypass
                    localparam integer LOW  = b_i * BYTE_WIDTH;
                    localparam integer HIGH = ((LOW + BYTE_WIDTH) > DATA_WIDTH) ? (DATA_WIDTH - 1) : (LOW + BYTE_WIDTH - 1);
                    always @(posedge clk_b) begin
                        if (en_b && we_b[b_i]) ram_data_b[HIGH:LOW] <= din_b[HIGH:LOW];
                    end
                end
            end
        end else begin : gen_portb_sdp
            // SIMPLE_DUAL일 때 Port B는 Read 전용
            always @(posedge clk_b) begin
                if (en_b) ram_data_b <= mem[addr_b];
            end
        end

        // Port B 내장 출력 레지스터 (BRAM Primitive 내부 임베디드 레지스터 매핑)
        if (REG_OUT_B == 1) begin : gen_reg_out_b
            always @(posedge clk_b) begin
                if (rst_b) begin
                    dout_b_reg <= {DATA_WIDTH{1'b0}};
                end else if (regce_b) begin
                    dout_b_reg <= ram_data_b;
                end
            end
            assign dout_b = dout_b_reg;
        end else begin : gen_no_reg_out_b
            assign dout_b = ram_data_b;
        end
    endgenerate

endmodule
