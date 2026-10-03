 module skid_buffer #( //범용적으로 사용할 skid buffer 모듈임. ready, valid 핸드쉐이크할때 사용할 예정임. 
    parameter DATA_WIDTH = 32
) (
    input  wire                  clk,
    input  wire                  reset, //동기식 active high reset

    // Upstream (Slave) Interface
    input  wire                  s_valid,
    output wire                  s_ready,
    input  wire [DATA_WIDTH-1:0] s_data,

    // Downstream (Master) Interface
    output reg                   m_valid,
    input  wire                  m_ready,
    output reg  [DATA_WIDTH-1:0] m_data
);

    // Skid/Spare storage
    reg [DATA_WIDTH-1:0] skid_data;
    reg                  skid_valid;

    // Upstream ready: skid 레지스터가 비어있으면 항상 수신 가능
    assign s_ready = !skid_valid;

    always @(posedge clk) begin
        if (reset) begin
            m_valid    <= 1'b0;
            skid_valid <= 1'b0;
            m_data     <= {DATA_WIDTH{1'b0}};
            skid_data  <= {DATA_WIDTH{1'b0}};
        end else begin
            // 1. Skid Register Update
            if (s_valid && s_ready) begin
                if (m_valid && !m_ready) begin
                    // Downstream이 막혀있는데 새 데이터가 들어오면 skid에 백업
                    skid_valid <= 1'b1;
                    skid_data  <= s_data;
                end
            end else if (m_ready) begin
                // Downstream이 데이터를 가져가면 skid는 비워짐
                skid_valid <= 1'b0;
            end

            // 2. Main Output Register Update
            if (m_ready || !m_valid) begin
                if (skid_valid) begin
                    // Skid에 대기 중이던 '다음 순서' 데이터를 출력단으로 승격
                    m_valid <= 1'b1;
                    m_data  <= skid_data;
                end else if (s_valid) begin
                    // Skid가 비어있으면 들어오는 입력을 곧바로 출력단에 적재
                    m_valid <= 1'b1;
                    m_data  <= s_data;
                end else begin
                    m_valid <= 1'b0;
                end
            end
        end
    end

endmodule
