// =============================================================================
// Module: pipe_delay
// Description:
//   - Configurable pipeline delay (shift register) module for arbitrary data width.
//   - Supports 0-cycle latency (bypass wire) up to N-cycle latency.
//   - Includes active-low stall (or active-high clock enable) for backpressure.
// =============================================================================
module pipe_delay #(
    parameter integer WIDTH  = 16, // 전달할 데이터 비트 폭
    parameter integer STAGES = 1   // 지연시킬 클럭 사이클 수 (0: 바이패스, 1 이상: 플립플롭 체인)
)(
    input  wire              clk,
    input  wire              reset,    // 동기식 Active-High 리셋
    input  wire              en,     // 1: 정상 동작(Shift), 0: 파이프라인 정지(Freeze/Hold)
    input  wire [WIDTH-1:0]  din,
    output wire [WIDTH-1:0]  dout
);

    generate
        // ---------------------------------------------------------------------
        // Case 1: 0-cycle Delay (Bypass Mode)
        // ---------------------------------------------------------------------
        if (STAGES == 0) begin : gen_bypass
            assign dout = din;
        end

        // ---------------------------------------------------------------------
        // Case 2: 1-cycle Delay (Single D-FF)
        // ---------------------------------------------------------------------
        else if (STAGES == 1) begin : gen_single_stage
            reg [WIDTH-1:0] pipe_r;

            always @(posedge clk) begin
                if (reset) begin
                    pipe_r <= {WIDTH{1'b0}};
                end else if (en) begin
                    pipe_r <= din;
                end
            end

            assign dout = pipe_r;
        end

        // ---------------------------------------------------------------------
        // Case 3: N-cycle Delay (Multi-stage Shift Register Array)
        // ---------------------------------------------------------------------
        else begin : gen_multi_stage
            reg [WIDTH-1:0] pipe_r [0:STAGES-1];
            integer i;

            always @(posedge clk) begin
                if (reset) begin
                    for (i = 0; i < STAGES; i = i + 1) begin
                        pipe_r[i] <= {WIDTH{1'b0}};
                    end
                end else if (en) begin
                    pipe_r[0] <= din;
                    for (i = 1; i < STAGES; i = i + 1) begin
                        pipe_r[i] <= pipe_r[i-1];
                    end
                end
            end

            assign dout = pipe_r[STAGES-1];
        end
    endgenerate

endmodule