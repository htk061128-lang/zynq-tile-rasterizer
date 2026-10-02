module priority_encoder #( //일단 직관적으로 구현하고, 합성기가 알아서 최적화 안해주면 나중에 계층적 트리구조로 다시 작성하면 될 듯.
    parameter INPUT_WIDTH = 32,
    localparam OUTPUT_WIDTH = $clog2(INPUT_WIDTH)
)( 
    input  wire [INPUT_WIDTH-1:0] in, //가장 MSB에 가까운 1인 비트의 이진 인덱스를 반환함. 만약 in이 32비트면 0 ~ 31사이의 4비트 out을 반환함.
    output reg  [OUTPUT_WIDTH-1:0]  out, 
    output wire        valid //in의 모든 비트가 싹 다 0이면 valid는 0임. 
);
    assign valid = |in;

    integer i;
    always @(*) begin
        out = 5'd0;
        for (i = 0; i < INPUT_WIDTH; i = i + 1) begin
            if (in[i]) begin
                out = i[OUTPUT_WIDTH-1:0];
            end
        end
    end
endmodule