module division_using_reciprocal #(
    //나누는 수는 전부 1보다 큰 양수이던가, 1보다 작은 양수여야 함!!! 
    //그래야 reciprocal_maker 모듈을 사용해서 역수를 높은 정확도로 구할 수 있음. 
    //나눗셈이 필요한 구간은 invDet 구할때, 1/z로 나눌때, z로 나눌때임. 각각 IS_BIG_THAN_1을 1, 0, 1 으로 설정해야 함!!!!
    //Det은 음수거나 1보다 작은 수면 그냥 버리는거고, 1/z도 0~1 사이의 값임. z도 1이하는 그냥 버리는거고. 

    parameter NUM_CHANNELS    = 2,  // 피제수 개수

    parameter NUM_WIDTH       = 24, // 피제수(Numerator) 전체 비트폭
    parameter NUM_FRAC        = 8,  // 피제수 소수점 비트수 (QN_INT.NUM_FRAC)
    parameter NUM_SIGNED      = 1,  // 1: Signed (X, Y, UV 등), 0: Unsigned

    parameter DEN_WIDTH       = 32, // 제수(Denominator) 전체 비트폭 (Det, Z, 1/Z)
    parameter DEN_FRAC        = 16,  // 제수 소수점 비트수
    parameter IS_BIG_THAN_1   = 1,  // 1: D >= 1.0 (Det, Z), 0: 0 < D < 1.0 (1/Z). 제수는 무조건 양수임!!!

    //IS_BIG_THAN_1과 합이 맞아야 함!!. 제수가 1보다 크면 RECIP_FRAC = RECIP_WIDTH여야 하는거고, 1보다 작으면 정수부를 뭐 한 9비트 정도로 많이 할당해야 함!! 
    parameter RECIP_WIDTH     = 25, // reciprocal_maker가 출력하는 1/D 비트폭 (DSP48E1 B포트 최적화: 18b)
    parameter RECIP_FRAC      = 25, // 1/D의 소수점 비트수
    parameter NEWTON_RAPHSON = 0, //newton_raphson을 설정하면 총 스테이지 수가 늘어남!!!(reciprocal_maker에서 아직 구현되지 않았음.)

    parameter OUT_WIDTH       = 16, // 최종 몫(Q) 비트폭 
    parameter OUT_FRAC        = 8,  // 최종 몫 소수점 비트수
    parameter OUT_SIGNED      = 1  // 1: Signed, 0: Unsigned
)(
    input clk,
    input reset,

    input in_valid,
    // [NUM_CHANNELS * NUM_WIDTH - 1 : 0] 형태로 묶어서 넣어줘야 함. {data1, data0} 이렇게.
    input  wire [NUM_CHANNELS*NUM_WIDTH-1:0] in_numerators, 
    input  wire [DEN_WIDTH-1:0] in_denominator, // 공통 제수 1개

    output wire out_valid,
    output wire [NUM_CHANNELS*OUT_WIDTH-1:0] out_quotients,
    output wire [NUM_CHANNELS-1:0] out_overflow

);
endmodule