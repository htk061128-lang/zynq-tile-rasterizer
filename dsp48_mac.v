`timescale 1ns / 1ps

// ============================================================================
// Module: dsp48_mac
// Description:
//   Xilinx 7-Series DSP48E1 Slice Behavioral Inference Template
//   - Input A: 25-bit signed (행렬 성분, 계수 등)
//   - Input B: 18-bit signed (정점 좌표, 입력 샘플 등)
//   - Input C: 48-bit signed (평행이동 성분, 초기 바이어스 등)
//   - Output P: 48-bit signed (P = A * B + (clr_accum ? (load_c ? C : 0) : P))
//
// Pipeline Latency: 3 Cycles (AREG/BREG -> MREG -> PREG)
// ============================================================================

//FPGA의 DSP로 합성되야 하는 모듈임.

module dsp48_mac ( //범용 25 * 18 비트 DSP 모듈. a_in, b_in, c_in은 무조건 signed 값으로 줘야 하고 내부에 레지스터가 3개여서 클럭에지 3번 후에 p_out이 나옴. 
    input  wire               clk,
    input  wire               rst_n,      // Active Low 동기/비동기 리셋

    // 제어 신호 (파이프라인 지연을 고려해 인입)
    input  wire               clr_accum,  // Clear Accumulator(누산기 초기화).
    // 1: 누산 초기화 (새로운 내적/벡터 시작), 3클럭후 p_out = c_in +  (a_in * b_in) 
    // 0: 전 클럭의 곱셈값을 현재 a_in, b_in의 곱과 누적함.
    // 즉 연속으로 a1, b1, 다음클럭에 a2, b2, 다음클럭에 a3, b3를 넣어주면 그 다음클럭에 a1 * b1, 다음클럭에 (a1 * b1) + (a2 * b2), 다음클럭에 (a1 * b1) + (a2 * b2) + (a3 * b3)가 p_out으로 나오는 구조임. 
    input  wire               load_c,     
    // 1: 누산 초기화 시 C 입력값을 베이스로 로드 (A*B + C)
    // 0: 누산 초기화 시 0에서 시작 (A*B + 0), 즉 clr_accum이 0이면 load_c가 1이던 0이건 그냥 무시됨.. 

    // 데이터 입력
    (* use_dsp = "yes" *)
    input  wire signed [24:0] a_in,       // 25-bit Signed
    input  wire signed [17:0] b_in,       // 18-bit Signed
    input  wire signed [47:0] c_in,       // 48-bit Signed (미사용 시 48'sd0)

    // 결과 출력
    output wire signed [47:0] p_out,      // 48-bit Signed P 출력
    output wire               valid_out   // 출력 유효 플래그
);

    // ------------------------------------------------------------------------
    // Stage 1: Input Registers (DSP48 A/B/C Registers)
    // ------------------------------------------------------------------------
    reg signed [24:0] a_reg;
    reg signed [17:0] b_reg;
    reg signed [47:0] c_reg;
    reg               clr_accum_d1;
    reg               load_c_d1;
    reg               valid_d1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_reg        <= 25'sd0;
            b_reg        <= 18'sd0;
            c_reg        <= 48'sd0;
            clr_accum_d1 <= 1'b0;
            load_c_d1    <= 1'b0;
            valid_d1     <= 1'b0;
        end else begin
            a_reg        <= a_in;
            b_reg        <= b_in;
            c_reg        <= c_in;
            clr_accum_d1 <= clr_accum;
            load_c_d1    <= load_c;
            valid_d1     <= 1'b1;
        end
    end

    // ------------------------------------------------------------------------
    // Stage 2: Multiplier Register (DSP48 M Register)
    // 25-bit * 18-bit = 43-bit 부호 곱셈
    // ------------------------------------------------------------------------
    reg signed [42:0] m_reg;
    reg signed [47:0] c_reg_d2;
    reg               clr_accum_d2;
    reg               load_c_d2;
    reg               valid_d2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_reg        <= 43'sd0;
            c_reg_d2     <= 48'sd0;
            clr_accum_d2 <= 1'b0;
            load_c_d2    <= 1'b0;
            valid_d2     <= 1'b0;
        end else begin
            m_reg        <= a_reg * b_reg; // DSP 내부 전용 고속 곱셈기
            c_reg_d2     <= c_reg;
            clr_accum_d2 <= clr_accum_d1;
            load_c_d2    <= load_c_d1;
            valid_d2     <= valid_d1;
        end
    end

    // ------------------------------------------------------------------------
    // Stage 3: Accumulator / Output Register (DSP48 P Register)
    // ------------------------------------------------------------------------
    reg signed [47:0] p_reg;
    reg               valid_d3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p_reg    <= 48'sd0;
            valid_d3 <= 1'b0;
        end else begin
            valid_d3 <= valid_d2;

            if (clr_accum_d2) begin
                if (load_c_d2) begin
                    // A * B + C (평행이동 값을 바로 얹고 시작할 때)
                    p_reg <= m_reg + c_reg_d2;
                end else begin
                    // A * B + 0 (단순 곱셈으로 누산 리셋)
                    p_reg <= {{5{m_reg[42]}}, m_reg};
                end
            end else begin
                // P + A * B (기존 P값에 누적 덧셈)
                p_reg <= p_reg + m_reg;
            end
        end
    end

    assign p_out     = p_reg;
    assign valid_out = valid_d3;

endmodule
