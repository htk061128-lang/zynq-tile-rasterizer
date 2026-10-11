module reciprocal_maker #( //입력 데이터의 역수를 BRAM으로 구성된 룩업테이블을 읽고 변형해서 출력하는 모듈. 반드시 unsigned 값으로 들어와야 함!
    //입력 포맷 파라미터 (Unsigned)
    parameter INPUT_WIDTH_A       = 32, // A포트의 입력 데이터 비트 수
    parameter IN_INTEGER_BITS_A   = 16, // 입력 정수부 비트 수
    parameter IN_FRAC_BITS_A      = 16, // 입력 소수부 비트 수 (IN_INTEGER_BITS_A + IN_FRAC_BITS_A == INPUT_WIDTH_A)

    parameter INPUT_WIDTH_B       = 32, // A포트의 입력 데이터 비트 수
    parameter IN_INTEGER_BITS_B   = 16, // 입력 정수부 비트 수
    parameter IN_FRAC_BITS_B      = 16, // 입력 소수부 비트 수 (IN_INTEGER_BITS_B + IN_FRAC_BITS_B == INPUT_WIDTH_B)

    //출력 포맷 파라미터 (Unsigned)
    parameter OUTPUT_WIDTH_A      = 18, // A포트의 출력 역수 비트 수. 무조건 18 이상이어야 함!!!
    parameter OUT_INTEGER_BITS_A  = 0,  // 출력 정수부 비트 수 (보통 0~1)
    parameter OUT_FRAC_BITS_A     = 18, // 출력 소수부 비트 수 (OUT_INTEGER_BITS_A + OUT_FRAC_BITS_A == OUTPUT_WIDTH_A)

    parameter OUTPUT_WIDTH_B      = 18, // B포트의 출력 역수 비트 수. 무조건 18 이상이어야 함!!!
    parameter OUT_INTEGER_BITS_B  = 0,  // 출력 정수부 비트 수 (보통 0~1)
    parameter OUT_FRAC_BITS_B     = 18, // 출력 소수부 비트 수 (OUT_INTEGER_BITS_B + OUT_FRAC_BITS_B == OUTPUT_WIDTH_B)

    parameter INTERNAL_SHIFT_A = 1, //이 값을 1로 설정하면 6개의 파이프라인 레지스터를 지난 후 출력포맷 파라미터 규격에 맞춰진 값이 나옴.
    //그리고 이 값이 0이면 5개의 파이프라인 레지스터를 지난 후 18비트 UQ0.18규격의 역수값과 out_rshift값이 나옴.
    parameter INTERNAL_SHIFT_B = 1, //이 값이 1이면 0일때 사용되는 output신호는 사용되지 않고, 0이면 1일떄 사용되는 output신호는 사용되지 않음!!


    //연산 파라미터
    parameter NEWTON_RAPHSON_PORT_A = 0,   // PORT A의 NR 반복 횟수: 0 (11bit 정밀도), 1 (22bit 정밀도), 2 (44bit 정밀도)
    parameter NEWTON_RAPHSON_PORT_B = 0,

    localparam SHIFT_W_A = $clog2(INPUT_WIDTH_A), //쉬프트할 비트수를 저장하기 위해 필요함. 
    localparam SHIFT_W_B = $clog2(INPUT_WIDTH_B) //쉬프트할 비트수를 저장하기 위해 필요함. 
)( //합성시 내부의 BRAM을 해당하는 18비트 역수가 들어있게 초기화 해두어야 함!
    // $clog2()는 주어진 숫자를 표현하거나 메모리를 주소 지정하는 데 필요한 최소 비트 수(올림된 log2_() 값)를 계산하는
    // 베릴로그(Verilog) 시스템 함수임.
    input clk,
    input reset, //동기식 active high reset

    // ------ Port A 입력 스트림 --------
    input  wire in_valid_a,
    input  wire [INPUT_WIDTH_A-1:0] in_data_a, //무조건 플립플롭의 출력을 바로 input으로 보내야 함. 조합논리 지난 값을 주면 안됨!!!

    // ------ Port A 출력 스트림 --------
    output reg out_valid_a,
    output reg div_by_zero_a, // in_data가 0일 때의 예외 플래그

    //INTERNAL_SHIFT_A = 1일때만 유효함!!
    output wire [OUTPUT_WIDTH_A-1:0] out_after_reciprocal_a, //쉬프트가 완료되고, parameter에 의한 고정소수점 규격을 만족하는 출력신호.

    //INTERNAL_SHIFT_A = 0일때만 유효함!!
    output wire [17:0] out_pre_reciprocal_a, //정규화된 1/M (UQ0.18) (BRAM에서 읽어온 꽉 찬 18비트, 유효 비트 전부 보존)
    output wire signed [SHIFT_W_A:0] out_rshift_a, //나중에 우측으로 쉬프트해야 하는 비트수. 음수이면 왼쪽으로 쉬프트 해야함. 
    //out_data_a가 UQ0.18이기 때문에 쉬프트가 없으면 out_pre_reciprocal_a[18]위치가 본래 2^0 성분임.

    // ------- Port B 입력 스트림 --------
    input  wire in_valid_b,
    input  wire [INPUT_WIDTH_B-1:0] in_data_b,

    // ------- Port B 출력 스트림 ---------
    output reg out_valid_b,
    output reg div_by_zero_b, 

    //INTERNAL_SHIFT_A = 1일때만 유효함!!
    output wire [OUTPUT_WIDTH_B-1:0] out_after_reciprocal_b,

    //INTERNAL_SHIFT_A = 0일때만 유효함!!
    output wire [17:0] out_pre_reciprocal_b, 
    output wire signed [SHIFT_W_B:0] out_rshift_b

);
//Newton-Raphson을 1번 적용할때마다 DSP가 포트당 2개씩 사용됨. 파이프라인 구조를 생각하고 만들어서 매 클럭 값을 넣어도 됨. 
//Newton-Raphson 사용하지 않으면 내부 쉬프트를 사용할경우 6단계의 파이프라인 레지스터를 지난 후 출력이 나오고,
//내부 쉬프트를 사용하지 않은경우 5단계의 파이프라인 레지스터를 지난후 18비트 UQ0.18값과 out_rshift값이 나옴.

// 18-bit x 2048 Reciprocal Look-Up Table (Total: 36,864 bits = 1x BRAM36K)
wire [10:0] bram_ad_a = sam_ad_a_ff[10:0]; // 11비트 주소 입력
wire [17:0] bram_r_data_a; // 18비트 역수 데이터 출력 (2 클럭 지연)
wire bram_en_a = ~is_zero_a_ff; // 파이프라인 유효 신호 연동

wire [10:0] bram_ad_b; // 11비트 주소 입력
wire [17:0] bram_r_data_b; // 18비트 역수 데이터 출력 (2 클럭 지연)
wire bram_en_b; // 파이프라인 유효 신호 연동

generic_bram #(
    .DATA_DEPTH(2048),                    // 18 * 2028 BRAM 사용.
    .DATA_WIDTH(18),                      // 18비트 데이터 폭
    .BYTE_WIDTH(9),                       // 9비트 단위 바이트 인에이블 (총 2비트 we)
    .RAM_MODE("TRUE_DUAL"),             // TRUE DUAL 포트 사용. 
    .WRITE_MODE("NO_CHANGE"),             // 저전력 / 고속 권장 모드
    .REG_OUT_A(1), // 출력 레지스터 활성화 (Latency: 2 클럭)
    .REG_OUT_B(1), // 출력 레지스터 활성화 (Latency: 2 클럭)
    .INIT_FILE("reciprocal_18x2048.hex") // 2048 엔트리 초기화 파일
) u_reciprocal_lut (
        // Port A 
    .clk_a       (clk),
    .en_a        (bram_en_a), // 읽기 활성화 (상시 1'b1 또는 파이프라인 enable)
    .regce_a     (1'b1), // 출력 파이프라인 레지스터 클럭 인에이블
    .rst_a       (reset), // 동기식 하이 리셋
    .we_a        (2'b00), // 쓰기 사용하지 않음.
    .addr_a      (bram_ad_a), // [10:0] 정규화된 11비트 주소
    .din_a       (18'b0), // 쓰기 사용 X
    .dout_a      (bram_r_data_a), // [17:0] 초기 역수 추정값 출력

        // Port B 
    .clk_b       (clk),
    .en_b        (bram_en_b),
    .regce_b     (1'b1),
    .rst_b       (reset),
    .we_b        (2'b00), //쓰기는 사용하지 않음.
    .addr_b      (bram_ad_b),
    .din_b       (18'b0), // 쓰기 사용 X
    .dout_b      (bram_r_data_b)                         
);

priority_encoder #( 
    .INPUT_WIDTH(INPUT_WIDTH_A)
) priority_encoder_ins (
    .in(in_data_a), //input신호를 바로 여기에 넣음.
    .out(pri_en_out_a_comb), //비트폭은 $clog2(INPUT_WIDTH_A)임.
    .valid() //in_data_a의 모든 비트가 0이면 valid는 0이 나옴. 어차피 is_zero_a_ff가 있으므로 받을 필요 없음.
);
wire [SHIFT_W_A-1:0] pri_en_out_a_comb; 

//우선순위 인코더는 32비트정도는 LUT 2 ~ 3단 이면 끝난다고 함. 배럴 쉬프터도 2 ~ 3단 이러고 함. gemini 피셜.

//PORT A 신호들 ---------------------------
//stage 1
reg [INPUT_WIDTH_A-1:0] in_data_a_ff; // in_data_a를 처음에 저장하는 레지스터. 뉴텁 랜손할때 필요해서 계속 보내줘야 함.
reg [SHIFT_W_A-1:0] pri_encoder_index_a_ff; //입력신호에 우선순위 인코더 돌려서 온 출력을 저장함. 
reg in_valid_a_ff; //in_valid_a를 처음에 저장하는 레지스터. 끝까지 보내줘야 함.

//stage 2
reg [10:0] sam_ad_a_ff; //유효한 11비트를 샘플링해서 저장하는 레지스터.
reg signed [SHIFT_W_A:0] rshift_a_ff; //나중에 오른쪽으로 쉬프트 해야하는 비트 개수를 저장함. 음수면 왼쪽임!!! 그리고 부호를 위해 1비트 확장함!!! 진짜 주의해야 함.
reg is_zero_a_ff; //in_data_a_ff가 0이면 1을 저장함. 바로 인버터를 지나서 bram_en_a로 연결됨.
reg [INPUT_WIDTH_A-1:0] in_data_a_d1_ff; //나중에 필요한 값이므로 지연시킴.
reg in_valid_a_d1_ff; //나중에 필요한 값이므로 지연시킴.

wire [SHIFT_W_A-1:0] Leading_Zero_Count_a_comb = SHIFT_W_A'(INPUT_WIDTH_A - 1) - pri_encoder_index_a_ff; //LSB부터의 비트 인덱스 pri_encoder_index_a_ff를 MSB부터의 비트 인덱스로 변경.
wire [INPUT_WIDTH_A-1:0] normalized_a_comb = in_data_a_ff << Leading_Zero_Count_a_comb; //MSB가 1이 되도록 왼쪽으로 쉬프트. Barrel Shifter;
wire signed [SHIFT_W_A:0] final_exponent_a_comb = $signed({1'b0, pri_encoder_index_a_ff}) - $signed({1'b0, SHIFT_W_A'(IN_FRAC_BITS_A)});
//in_data_a_ff[pri_encoder_index_a_ff] 비트는 정규화 후 2^0 성분의 위치이고, in_data_a_ff[IN_FRAC_BITS_A] 비트는 정규화 전 2^0 성분의 위치이므로 그 차가 P임.
//A(12비트 UQ1.11, 정수부 비트는 1, 범위는 1~1.9999) * 2^P로 정규화 할때의 P를 구함. 
//이 값의 역수는 1/A(18비트 UQ0.18 BRAM 읽기값) * 2^-P 이므로 나중에 결과값을 P만큼 오른쪽으로 쉬프트 해줘야 함. P값이 음수이면 왼쪽으로 쉬프트 해주면 됨.

//stage 3, BRAM 지연임.
reg [INPUT_WIDTH_A-1:0] in_data_a_d2_ff;
reg in_valid_a_d2_ff;
reg signed [SHIFT_W_A:0] rshift_a_d1_ff; //여기는 stage 2값이므로 첫번째 지연임.
reg is_zero_a_d1_ff;  //여기는 stage 2값이므로 첫번째 지연임.

//stage 4, BRAM 지연임.
reg [INPUT_WIDTH_A-1:0] in_data_a_d3_ff;
reg in_valid_a_d3_ff;
reg signed [SHIFT_W_A:0] rshift_a_d2_ff; 
reg is_zero_a_d2_ff;

//stage 5 부터는 generate문에 의해서 진행됨.

integer i;
generate
    if(NEWTON_RAPHSON_PORT_A == 0) begin : nr_0 //port a가 newton-raphson을 사용하지 않을때. DSP 0개 사용

        if(INTERNAL_SHIFT_A == 1) begin : intershift //내부 쉬프트 파라미터를 켰을때
            assign out_pre_reciprocal_a = 0; //사용하지 않는 신호.
            assign out_rshift_a = 0;  //사용하지 않는 신호.
            assign out_after_reciprocal_a = out_after_reciprocal_a_ff;

            //stage 5. BRAM의 출력 레지스터에서 나온값 저장.
            reg [17:0] rdata_a_ff; //BRAM에서 읽어온 18비트 역수값(18비트 고정소수점. 0.5 ~ 1사이의 값임.) 저장하는 레지스터. 뉴턴랩스 하려면 필요함.
            reg [INPUT_WIDTH_A-1:0] in_data_a_d4_ff;
            reg in_valid_a_d4_ff;
            reg signed [SHIFT_W_A:0] rshift_a_d3_ff; 
            reg is_zero_a_d3_ff;

            //stage 6. 여기서 out_after_reciprocal_a, out_valid_a 를 출력함!!!
            reg [OUTPUT_WIDTH_A-1:0] out_after_reciprocal_a_ff;
            
            localparam signed FORMAT_OFFSET_A = 18 - OUT_FRAC_BITS_A; //출력을 OUTPUT의 비트크기에 맞춰서 내기위해서 필요한 상수. 출력의 소수점이 16비트면 오른쪽으로 2비트 밀어서 비트 2개를 날려줘야 16비트에 맞춰짐.
            wire signed [SHIFT_W_A+1:0] total_shift_a_comb = rshift_a_d3_ff + FORMAT_OFFSET_A; //FOTMAT_OFFSET_A를 더해서 최종 쉬프트 비트수를 구함. FORMAT_OFFSET_A를 더했으므로 1비트 확장함.
            wire is_negative_a_comb = total_shift_a_comb[SHIFT_W_A+1]; // MSB (부호 비트). 부호에 따라서 오른쪽 쉬프트인지 왼쪽 쉬프트인지 결정함. 
            wire [SHIFT_W_A+1:0] neg_total_shift_a_comb = -total_shift_a_comb;
            wire [SHIFT_W_A-1:0] abs_shift_a_comb = is_negative_a_comb ? (neg_total_shift_a_comb[SHIFT_W_A-1:0]) : total_shift_a_comb[SHIFT_W_A-1:0]; //rshift
            wire [OUTPUT_WIDTH_A-1:0] ext_rdata_a_comb = { {(OUTPUT_WIDTH_A-18){1'b0}}, rdata_a_ff }; //18비트 rdata_a_ff를 [OUTPUT_WIDTH_A-1:0] 범위로 확장.
            wire [OUTPUT_WIDTH_A-1:0] shifted_val_a_comb = is_negative_a_comb ? (ext_rdata_a_comb << abs_shift_a_comb) : (ext_rdata_a_comb >> abs_shift_a_comb);        

            always @(posedge clk) begin
                if(reset) begin
                    //stage 5
                    rdata_a_ff <= 0;
                    in_data_a_d4_ff <= 0;
                    in_valid_a_d4_ff <= 0;
                    rshift_a_d3_ff <= 0;
                    is_zero_a_d3_ff <= 0;

                    //stage 6
                    out_after_reciprocal_a_ff <= 0;
                    out_valid_a <= 0;
                    div_by_zero_a <= 0;
                end
                else begin
                    //stage 5.
                    rdata_a_ff <= bram_r_data_a; //bram에서 읽은 18비트 0.5 ~ 1 사이의 고정소수점 값 저장.
                    in_data_a_d4_ff <= in_data_a_d3_ff;
                    in_valid_a_d4_ff <= in_valid_a_d3_ff;
                    rshift_a_d3_ff <= rshift_a_d2_ff;
                    is_zero_a_d3_ff <= is_zero_a_d2_ff;

                    //stage 6. output으로 출력!!!
                    out_after_reciprocal_a_ff <= shifted_val_a_comb;
                    out_valid_a <= in_valid_a_d4_ff;
                    div_by_zero_a <= is_zero_a_d3_ff;
                end
            end
        end

        if(INTERNAL_SHIFT_A == 0) begin : noshift
            assign out_after_reciprocal_a = 0; //사용하지 않는 신호.
            assign out_pre_reciprocal_a = out_pre_reciprocal_a_ff; 
            assign out_rshift_a = out_rshift_a_ff;  

            reg [17:0] out_pre_reciprocal_a_ff; 
            reg signed [SHIFT_W_A:0] out_rshift_a_ff;

            always @(posedge clk) begin
                if(reset) begin
                    //stage 5.
                    out_rshift_a_ff <= 0;
                    out_pre_reciprocal_a_ff <= 0;
                    out_valid_a <= 0;
                    div_by_zero_a <= 0;
                end
                else begin
                    out_pre_reciprocal_a_ff <= bram_r_data_a;
                    out_rshift_a_ff <= rshift_a_d2_ff;
                    out_valid_a <= in_valid_a_d3_ff;
                    div_by_zero_a <= is_zero_a_d2_ff;
                end
            end
        end


        always @(posedge clk) begin //INTERNAL_SHIFT_A와 관계없는 공통 부분들. stage 4 까지는 공통임.
            if(reset) begin
                in_data_a_ff <= 0;
                in_valid_a_ff <= 0;
                pri_encoder_index_a_ff <= 0;

                sam_ad_a_ff <= 0;
                rshift_a_ff <= 0;
                is_zero_a_ff <= 0;
                in_data_a_d1_ff <= 0;
                in_valid_a_d1_ff <= 0;

                in_data_a_d2_ff <= 0;
                in_valid_a_d2_ff <= 0;
                rshift_a_d1_ff <= 0;
                is_zero_a_d1_ff <= 0;

                in_data_a_d3_ff <= 0;
                in_valid_a_d3_ff <= 0;
                rshift_a_d2_ff <= 0;
                is_zero_a_d2_ff <= 0;
            end
            else begin
                //stage 1
                in_data_a_ff <= in_data_a;
                in_valid_a_ff <= in_valid_a;
                pri_encoder_index_a_ff <= pri_en_out_a_comb; //priority encoder에서 나온 출력을 바로 저장함. 

                //stage 2
                sam_ad_a_ff[10:0] <= normalized_a_comb[INPUT_WIDTH_A-2:INPUT_WIDTH_A-12]; //11비트 추출해서 저장. 이때 MSB는 정수부 1이고 이후의 11비트 소수부를 사용함.
                is_zero_a_ff <= (in_data_a_ff == 0);
                rshift_a_ff <= final_exponent_a_comb;
                in_data_a_d1_ff <= in_data_a_ff;
                in_valid_a_d1_ff <= in_valid_a_ff;

                //stage 3. BRAM 지연
                in_data_a_d2_ff <= in_data_a_d1_ff;
                in_valid_a_d2_ff <= in_valid_a_d1_ff;
                rshift_a_d1_ff <= rshift_a_ff;
                is_zero_a_d1_ff <= is_zero_a_ff;

                //stage 4. BRAM 지연
                in_data_a_d3_ff <= in_data_a_d2_ff;
                in_valid_a_d3_ff <= in_valid_a_d2_ff;
                rshift_a_d2_ff <= rshift_a_d1_ff;
                is_zero_a_d2_ff <= is_zero_a_d1_ff;
            end
        end

    end
    else if(NEWTON_RAPHSON_PORT_A == 1) begin : nr_1 //port a가 newton-raphson을 1번 사용할때. DSP 2개 사용
    end
    else if(NEWTON_RAPHSON_PORT_A == 2) begin : nr_2 //port a가 newton-raphson을 2번 사용할때. DSP 4개 사용
    end
endgenerate

generate
    if(NEWTON_RAPHSON_PORT_B == 0) begin : nr_3 //port b가 newton-raphson을 사용하지 않을때. DSP 0개 사용
    end
    else if(NEWTON_RAPHSON_PORT_B == 1) begin : nr_4 //port b가 newton-raphson을 1번 사용할때. DSP 2개 사용
    end
    else if(NEWTON_RAPHSON_PORT_B == 2) begin : nr_5 //port b가 newton-raphson을 2번 사용할때. DSP 4개 사용
    end
endgenerate

endmodule