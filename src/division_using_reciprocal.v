module division_using_reciprocal #( //역수기, DSP 합쳐서 총 10단계의 파이프라인 레지스터를 통과함.
    //reciprocal_maker Port A 파라미터-------------------------------------
    //분자(Numerator)은 signed 값이어서 부호비트 1비트가 포함됨. 무조건 25비트 이하여야 함!!
    parameter NUM_CHANNELS_A    = 2, //동일한 제수로 나누어지는 피제수의 개수. 일단 최대 2개까지 설정 가능함.
    parameter NUM_WIDTH_A       = 25, //분자(Numerator), 나눠지는 수, 피제수 총 비트 수. 25비트를 넘으면 DSP에 넣지를 못해서 절대 안됨. 
    parameter NUM_FRAC_A        = 8, //분자의 소수점 비트 수

    //분모(Denominator)은 unsinged 값이어서 부호비트가 포함되지 않음.
    parameter DEN_WIDTH_A       = 32, //분모(Denominator), 나누는 수, 제수 총 비트 수
    parameter DEN_FRAC_A        = 16, //분모의 소수점 비트 수
    parameter IS_BIG_THAN_1_A   = 1, //역수기를 바탕으로 나눗셈이 수행되기에 1보다 큰지, 0 ~ 1사이인지 반드시 명시해야 함!!!

    //몫은 명시한 고정소수점 포맷으로 출력됨. (signed 값이라 부호비트 포함. OUT_WIDTH_A = 16, OUT_FRAC_A = 4 라면 SQ11.4 포맷으로 출력됨)
    //몫의 비트수는 48비트 이하여야 함!! DSP의 출력 비트수가 48비트이기 때문임.
    parameter OUT_WIDTH_A       = 16, //몫의 총 비트 수
    parameter OUT_FRAC_A        = 8, //몫의 소수점 비트 수

    //reciprocal_maker Port B 파라미터----------------------------------------
    //분자(Numerator)은 signed 값이어서 부호비트 1비트가 포함됨. DSP 스펙상 무조건 25비트 이하여야 함!!
    parameter NUM_CHANNELS_B    = 2, //일단 최대 2개까지 설정 가능함. 
    parameter NUM_WIDTH_B       = 25, 
    parameter NUM_FRAC_B        = 8,  

    //분모(Denominator)은 unsinged 값이어서 부호비트가 포함되지 않음.
    parameter DEN_WIDTH_B       = 32, 
    parameter DEN_FRAC_B        = 16,  
    parameter IS_BIG_THAN_1_B   = 0,  

    //몫은 명시한 고정소수점 포맷으로 출력됨. (signed 값이라 부호비트 포함. OUT_WIDTH_A = 16, OUT_FRAC_A = 4 라면 SQ11.4 포맷으로 출력됨)
    parameter OUT_WIDTH_B       = 16, 
    parameter OUT_FRAC_B        = 8
)(
    input clk,
    input reset, 

    //reciprocal_maker Port A 인터페이스
    input wire in_valid_a,
    input wire signed [NUM_CHANNELS_A*NUM_WIDTH_A-1:0] in_numerators_a, //signed 값임!!
    input wire unsigned [DEN_WIDTH_A-1:0] in_denominator_a, //1이상, 혹은 0 ~ 1 사이의 unsigned 값임!!

    output reg out_valid_a,
    output reg signed [NUM_CHANNELS_A*OUT_WIDTH_A-1:0] out_quotients_a, //signed 값임!
    output reg div_by_zero_a,

    //reciprocal_maker Port B 인터페이스
    input wire in_valid_b,
    input wire signed [NUM_CHANNELS_B*NUM_WIDTH_B-1:0] in_numerators_b, //signed 값임!!
    input wire unsigned [DEN_WIDTH_B-1:0] in_denominator_b, //1이상, 혹은 0 ~ 1 사이의 unsigned 값임!!

    output reg out_valid_b,
    output reg signed [NUM_CHANNELS_B*OUT_WIDTH_B-1:0] out_quotients_b, //signed 값임!!
    output reg div_by_zero_b
);
    localparam RECIP_OUT_WIDTH_A = 18;
    localparam RECIP_OUT_WIDTH_B = 18;
    
    // 역수 모듈에서 나올 포트 A 신호
    wire recip_out_valid_a;
    wire [17:0] out_pre_recip_a;
    wire signed [$clog2(DEN_WIDTH_A):0] out_rshift_a; 
    wire out_div_by_zero_a;

    // 역수 모듈에서 나올 포트 B 신호
    wire recip_out_valid_b;
    wire [17:0] out_pre_recip_b;
    wire signed [$clog2(DEN_WIDTH_B):0] out_rshift_b;
    wire out_div_by_zero_b;

    // Dual-Port Reciprocal Maker 인스턴스화
    reciprocal_maker #(
        // ---- Port A 설정 ----
        .INPUT_WIDTH_A(DEN_WIDTH_A),
        .IN_INTEGER_BITS_A(DEN_WIDTH_A - DEN_FRAC_A),
        .IN_FRAC_BITS_A(DEN_FRAC_A),
        .OUTPUT_WIDTH_A(RECIP_OUT_WIDTH_A), 
        .OUT_INTEGER_BITS_A(), //사용하지 않음!
        .OUT_FRAC_BITS_A(), //사용하지 않음!
        .INTERNAL_SHIFT_A(0), //내부 쉬프트 사용하지 않음!!! 따라서 18비트 UQ0.18값과 rshift값이 output으로 5단계의 파이프라인 레지스터를 지난후 나옴.
        .NEWTON_RAPHSON_PORT_A(0), //Newton_Raphson 사용하지 않음!!

        // ---- Port B 설정 ----
        .INPUT_WIDTH_B(DEN_WIDTH_B),
        .IN_INTEGER_BITS_B(DEN_WIDTH_B - DEN_FRAC_B),
        .IN_FRAC_BITS_B(DEN_FRAC_B),
        .OUTPUT_WIDTH_B(RECIP_OUT_WIDTH_B), 
        .OUT_INTEGER_BITS_B(), 
        .OUT_FRAC_BITS_B(),
        .INTERNAL_SHIFT_B(0), //내부 쉬프트 사용하지 않음!!! 따라서 18비트 UQ0.18값과 rshift값이 output으로 5단계의 파이프라인 레지스터를 지난후 나옴.
        .NEWTON_RAPHSON_PORT_B(0) //Newton_Raphson 사용하지 않음!!
    ) u_reciprocal_maker (
        .clk(clk),
        .reset(reset),

        // Port A 연결
        .in_valid_a(in_valid_a), //바로 reciprocal_maker 모듈로 넣어줌.
        .in_data_a(in_denominator_a), //바로 reciprocal_maker 모듈로 넣어줌.
        .out_valid_a(recip_out_valid_a),
        .div_by_zero_a(out_div_by_zero_a),
        .out_after_reciprocal_a(), //내부 쉬프트 사용하지 않으므로 사용되지 않는 신호임.
        .out_pre_reciprocal_a(out_pre_recip_a), //18비트 UQ0.18값임. 5단계 파이프라인 레지스터를 지난 후 출력됨.
        .out_rshift_a(out_rshift_a), //signed 값이고 양수면 우측 쉬프트, 음수면 좌측쉬프트라는 의미임.

        // Port B 연결
        .in_valid_b(in_valid_b),
        .in_data_b(in_denominator_b),
        .out_valid_b(recip_out_valid_b),
        .div_by_zero_b(out_div_by_zero_b),
        .out_after_reciprocal_b(), //내부 쉬프트 사용하지 않으므로 사용되지 않는 신호임.
        .out_pre_reciprocal_b(out_pre_recip_b), //18비트 UQ0.18값임
        .out_rshift_b(out_rshift_b)
    );

    pipe_delay #( //Port A의 파이프라인 지연 모듈
        .WIDTH(NUM_CHANNELS_A*NUM_WIDTH_A),
        .STAGES(5) //reciprocal_maker에서 5단계의 파이프라인 레지스터를 거치므로 동일하게 5단계를 거치게 설정함. 
    ) u_pipe_delay_a (
        .clk(clk),
        .reset(reset),
        .en(1'b1), //stall은 사용하지 않음. 그냥 버블로 제어함. 항상 파이프라인은 흐름.
        .din(pipe_delay_in_a),
        .dout(pipe_delay_out_a)
    );

    pipe_delay #( //Port B의 파이프라인 지연 모듈
        .WIDTH(),
        .STAGES(5) //reciprocal_maker에서 5단계의 파이프라인 레지스터를 거치므로 동일하게 5단계를 거치게 설정함. 
    ) u_pipe_delay_b (
        .clk(clk),
        .reset(reset),
        .en(1'b1), //stall은 사용하지 않음. 그냥 버블로 제어함. 항상 파이프라인은 흐름.
        .din(),
        .dout()
    );

    wire [NUM_CHANNELS_A*NUM_WIDTH_A-1:0] pipe_delay_in_a = {in_numerators_a}; //in_numerators_a 신호만 5단계 지연함.
    wire [NUM_CHANNELS_A*NUM_WIDTH_A-1:0] pipe_delay_out_a; 

    generate
        if(NUM_CHANNELS_A == 1) begin      
            // a_in (25-bit Signed): 피제수를 부호 확장해서 25비트로 할당
            wire signed [24:0] dsp_a_in = $signed(pipe_delay_out_a); //NUM_CHANNELS_A == 1 이기 때문에 분해해서 25비트 각각 확장 할 필요가 없음.

            // b_in (18-bit Signed): 역수 18비트 중 LSB를 버리고, MSB에 0을 채워 무조건 양수로 만듦
            wire signed [17:0] dsp_b_in = {1'b0, out_pre_recip_a[17:1]};

            wire signed [47:0] mult_result_a;
            wire mult_valid_a;

            dsp48_mac u_mult_a (
                .clk(clk),
                .reset(reset),
                .clr_accum(1'b1), // 누산 사용 X
                .load_c(1'b0),    // C 입력 사용 X
                .valid_in(recip_out_valid_a), //역수 유효 신호. reciprocal_maker의 출력신호가 바로 입력으로 들어감.
                
                .a_in(dsp_a_in), 
                .b_in(dsp_b_in),
                .c_in(48'sd0),    
                
                .p_out(mult_result_a), //총 합쳐서 8단계의 파이프라인 레지스터(역수 5 + 곱셈 3) 후에 출력이 나옴.
                .valid_out(mult_valid_a) 
            );
            // 역수를 >> 1 했으므로, 최종 정규화 시 우측 쉬프트 양을 1 줄여서(<< 1 효과) 보상함
            wire signed [$clog2(DEN_WIDTH_A):0] adjusted_rshift_a_comb = out_rshift_a - 1; //역수기 출력이므로 div_by_zero와 함께 3단계 지연시켜야 함.

            reg st60_div_by_zero_a_ff; //DSP 통과하는동안 역수변환기의 div_by_zero 출력을 지연시켜줌. 
            reg st60_adjusted_rshift_a_ff;
            reg st70_div_by_zero_a_ff;
            reg st70_adjusted_rshift_a_ff;
            reg st80_div_by_zero_a_ff;
            reg st80_adjusted_rshift_a_ff;

            reg signed [$clog2(DEN_WIDTH_A):0] st90_adjusted_rshift_a_ff;
            reg [47:0] st90_mult_result_a_ff;
            reg st90_valid_a_ff;
            reg st90_div_by_zero_a_ff;

            localparam signed [15:0] BASE_SHIFT_A = $signed(NUM_FRAC_A) + 17 - $signed(OUT_FRAC_A);
            //SQ0.17 * SQ(NUM_WIDTH - 1 - NUM_FRAC_A).(NUM_FRAC_A) 이므로 소수점 비트수는 NUM_FRAC_A + 17
            //이고 여기서 OUT_FRAC_A에 맞추기 위해서는 BASE_SHIFT_A만큼 우측으로 쉬프트 해야 함. 음수라면 좌측으로 쉬프트 해주면 됨. 
            wire signed [9:0] total_shift_a_comb = BASE_SHIFT_A + st80_adjusted_rshift_a_ff; //이때 곱한 역수값은 SQ0.17값 * 2^(-st90_adjusted_rshift_a_ff)이었음.
    
            wire signed [47:0] shifted_result_a_comb;
    
            // total_shift가 양수면 우측으로(>>>), 음수면 좌측으로(<<<) 산술 쉬프트
            assign shifted_result_a_comb = (total_shift_a_comb >= 0) ? 
                              (mult_result_a >>> total_shift_a_comb) : 
                              (mult_result_a <<< (-total_shift_a_comb));

            // OUT_WIDTH_A로 표현 가능한 최대/최소값 계산 (예: 16비트면 32767 / -32768)
            localparam signed [47:0] MAX_OUT_A = (1 << (OUT_WIDTH_A - 1)) - 1;
            localparam signed [47:0] MIN_OUT_A = -(1 << (OUT_WIDTH_A - 1));

            wire [NUM_CHANNELS_A*OUT_WIDTH_A-1:0] out_quotients_a_comb; //NUM_CHANNELS_A == 1임.

            // 오버플로/언더플로 발생 시 클램핑, 정상이면 하위 비트만 잘라서 몫으로 출력
            assign out_quotients_a_comb = (shifted_result_a_comb > MAX_OUT_A) ? MAX_OUT_A[OUT_WIDTH_A-1:0] :
                                    (shifted_result_a_comb < MIN_OUT_A) ? MIN_OUT_A[OUT_WIDTH_A-1:0] :
                                    shifted_result_a_comb[OUT_WIDTH_A-1:0];

            always @(posedge clk) begin
                if(reset) begin
                    st60_div_by_zero_a_ff <= 0;
                    st60_adjusted_rshift_a_ff <= 0;
                    st70_div_by_zero_a_ff <= 0;
                    st70_adjusted_rshift_a_ff <= 0;
                    st80_div_by_zero_a_ff <= 0;
                    st80_adjusted_rshift_a_ff <= 0;

                    //stage 9.
                    st90_adjusted_rshift_a_ff <= 0;
                    st90_div_by_zero_a_ff <= 0;
                    st90_mult_result_a_ff <= 0;
                    st90_valid_a_ff <= 0;

                    //stage 10.
                    out_valid_a <= 0;
                    out_quotients_a <= 0;
                    div_by_zero_a <= 0;
                end
                else begin
                    st60_div_by_zero_a_ff <= out_div_by_zero_a; //역수기 모듈의 출력인 out_div_by_zero_a 을 여기에 넣음.
                    st60_adjusted_rshift_a_ff <= adjusted_rshift_a_comb;
                    st70_div_by_zero_a_ff <= st60_div_by_zero_a_ff;
                    st70_adjusted_rshift_a_ff <= st60_adjusted_rshift_a_ff;
                    st80_div_by_zero_a_ff <= st70_div_by_zero_a_ff;
                    st80_adjusted_rshift_a_ff <= st70_adjusted_rshift_a_ff;
                    
                    st90_adjusted_rshift_a_ff <= st80_adjusted_rshift_a_ff;
                    st90_div_by_zero_a_ff <= st80_div_by_zero_a_ff;
                    st90_mult_result_a_ff <= mult_result_a; //DSP 모듈의 출력인 mul_result_a를 여기에 넣음.
                    st90_valid_a_ff <= mult_valid_a; //DSP 모듈의 출력인 mul_valid_a를 여기에 넣음.

                    out_valid_a <= st90_valid_a_ff;
                    out_quotients_a[NUM_CHANNELS_A*OUT_WIDTH_A-1:0] <= out_quotients_a_comb;
                    div_by_zero_a <= st90_div_by_zero_a_ff;
                end
            end
        end
        else if(NUM_CHANNELS_A == 2) begin
        end
    endgenerate

endmodule