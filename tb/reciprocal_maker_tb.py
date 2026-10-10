# This file is public domain, it can be freely copied without restrictions.
# SPDX-License-Identifier: CC0-1.0
# ruff: noqa: F841
# fmt: off
from __future__ import annotations

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb.queue import Queue

import random

golden_queue = Queue()

INPUT_FRAC = 16 #역수 변환전 값의 소수점 비트수. 예: UQ16.16
RECIPROCAL_FRAC = 25 #역수 변환후 값의 소수점 비트수. 예: UQ0.18
NUMERATOR_BEFORE_FRAC = 16 #피제수(나눠지는 수)의 원래 소수점 비트수. 예: SQ15.16
NUMERATOR_AFTER_FRAC = 10 #피제수(나눠지는 수)의 18비트나 25비트로 압축된 후 소수점 비트수 예: SQ9.8, SQ9.15등
OUTPUT_FRAC = 35 #나눗셈이 완료된 후 DSP결과값의 소수점 비트수. RECIPROCAL_FRAC + NUMERATOR_AFTER_FRAC

Z_MAX = 128 #(1 < Z < 128) : 128, (1 < Z < 256) : 256, (1 < Z < 512) : 512 등등 
X_MAX = 128 #(-128 < X < 128) : 128, (-256 < X < 256) : 256 등등, 


async def reset(dut):
    await RisingEdge(dut.clk)
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

def golden_model(indata, outdata):
    if indata == 0: return 444
    real_indata = indata / (2**INPUT_FRAC) #input의 소수점 비트수만큼으로 나눠야 함!!!
    real_outdata = outdata / (2**RECIPROCAL_FRAC) #output의 소수점 비트수만큼으로 나눠야 함!!!! 
    a = 1 / real_indata
    b = abs(((a - real_outdata) / a)) * 100 #절댓값이라서 양수로 나옴.
    return b, real_outdata, a #는 참값과의 오차율을 나타냄. %단위임.

def division_model(ideal_reciprocal, real_reciprocal): #real_reciprocal 값은 고정소수점 변환 전 정수값 받음. ideal_reciprocal은 변환 완료된 값 받음. 주의!!
    # 1. 원본 분자 생성 (SQ15.16 범위)
    numerator = random.randint((-X_MAX * (1 << NUMERATOR_BEFORE_FRAC)), 
                               ( X_MAX * (1 << NUMERATOR_BEFORE_FRAC)))
    
    # 2. 실수 기반 이상적 참값
    ideal_num = numerator / (1 << NUMERATOR_BEFORE_FRAC)
    ideal = ideal_reciprocal * ideal_num
    
    # 3. Verilog의 비트 슬라이싱 모사 (예: SQ15.16 -> 18비트/25비트로 절삭)
    #    하드웨어: assign after_num = numerator[BEFORE_WIDTH-1 : SHIFT];
    shift_in = NUMERATOR_BEFORE_FRAC - NUMERATOR_AFTER_FRAC
    
    # Verilog 비트 슬라이싱과 동일하게 하위 비트 버림 처리
    if numerator >= 0:
        after_num = numerator >> shift_in
    else:
        # 음수 절삭 (0을 향한 버림: Verilog의 Truncation과 동기화)
        after_num = -((-numerator) >> shift_in)
    
    # 4. DSP48E1 연산 모사 (Signed * Unsigned -> Signed 확장)
    dsp_mult_raw = int(real_reciprocal) * int(after_num)
    
    # 5. 최종 Q-포맷(OUTPUT_FRAC)에 맞춘 우측 산술 시프트
    shift_out = RECIPROCAL_FRAC + NUMERATOR_AFTER_FRAC - OUTPUT_FRAC
    
    if dsp_mult_raw >= 0:
        dsp_out = dsp_mult_raw >> shift_out
    else:
        dsp_out = -((-dsp_mult_raw) >> shift_out)
        
    real = dsp_out / (1 << OUTPUT_FRAC)
    
    # 6. 오차 판정 (화면 중앙 분모 0 폭발 방지)
    pixel_diff = abs(ideal - real) * 320 # 실제 화면에서 몇 픽셀 빗나갔는가?
    #pixel_diff = abs(ideal - real) # 실제 화면에서 몇 픽셀 빗나갔는가?
    return pixel_diff, real, ideal
    '''
    numerator = random.randint((-X_MAX * (2**16)), (X_MAX * (2**16))) # 
    #numerator = random.randint(1, (2**16) * (2**16)) #SQ15.16 랜덤 피제수값 생성!!
    ideal = (ideal_reciprocal) * (numerator / (2**NUMERATOR_BEFORE_FRAC))
    after_num = numerator >> (NUMERATOR_BEFORE_FRAC - NUMERATOR_AFTER_FRAC) ##18비트, 25비트등으로 자르면서 날라간 비트 쉬프트.
    dsp_out = (real_reciprocal * after_num) >> (RECIPROCAL_FRAC + NUMERATOR_AFTER_FRAC - OUTPUT_FRAC) #소수점 비트수가 DSP 후
    #RECIPROCAL_FRAC + NUMERATOR_AFTER_FRAC인 상황에서 소수점 비트수가 OUTPUT_FRAC인 정수로 변환하기 위해 쉬프트
    real = dsp_out / (2**(OUTPUT_FRAC))
    error_rate = abs(((ideal - real) / ideal)) * 100
    return error_rate, real, ideal
    '''


async def random_generate(dut): #input값 고정소수점 랜덤값 생성.
    #a = random.randint(1, 2**32 - 1) #32비트 정수를 랜덤으로 뽑음.
    a = 0
    while(a / (2**INPUT_FRAC) < 1):
        a = random.randint(1, (Z_MAX) * (2**INPUT_FRAC)) 
        #a = random.randint(1, (2**7) * (2**16)) #Z로 나눌때 Z값의 최대가 128일때 어떻게 되는지 확인용.
        #a = random.randint(1, (2**8) * (2**16)) #Z로 나눌때 Z값의 최대가 256일때 어떻게 되는지 확인용.
        #a = random.randint(1, (2**9) * (2**16)) #Z로 나눌때 Z값의 최대가 512일때 어떻게 되는지 확인용.
    #a = random.randint(1, (2**16)) #UQ16.16에서 정수부가 0인 소수부값이 들어갈때
    #a = random.randint(1, 2**18 - 1) #18비트 정수를 랜덤으로 뽑음.
    #a = random.randint(2**10, 2**18 - 1) #1/z이 1/256보다는 큰 상황
    #a = random.randint(2**9, 2**18 - 1) #1/z이 1/512보다는 큰 상황
    await golden_queue.put(a) #큐에 a를 넣음.

    await RisingEdge(dut.clk)
    dut.in_data_a.value = a #랜덤 값 넣어줌
    dut.in_valid_a.value = 1

async def monitor(dut, count=100000):
    checked_count = 0
    big_error_rate = 0
    division_diff = 0
    division_big_diff = 0;
    while checked_count < count:
        await RisingEdge(dut.clk)
        await Timer(1, "ns") # 엣지 직후 안정된 값 관찰

        if dut.out_valid_a.value == 1:
            in_val = await golden_queue.get() #큐에서 in_data_a값을 빼옴.
            error_rate, real, ideal = golden_model(in_val, int(dut.out_data_a.value))
            cocotb.log.info("checked_count: %d, 오차는 %f%%, 출력값: %f, 이상적인값: %f, 최고오차: %f", checked_count, error_rate, real, ideal, big_error_rate)
            division_diff, division_real, divison_ideal = division_model(ideal, int(dut.out_data_a.value))
            cocotb.log.info("checked_count: %d, 나눗셈 픽셀차: %fpixel, 나눗셈 출력: %f, 이상적인 값: %f, 최고 픽셀차: %fpixel", checked_count, division_diff, division_real, divison_ideal, division_big_diff)
            if error_rate > big_error_rate: big_error_rate = error_rate
            if division_diff > division_big_diff: division_big_diff = division_diff
            assert big_error_rate < 90
            checked_count += 1
        else: 
            cocotb.log.info("checked_count: %d, 현재 out_valid_a는 0", checked_count)

@cocotb.test
async def main_test(dut):
    # Start the clock running concurrently to the main test coroutine.
    Clock(dut.clk, 10, "ns").start()
    cocotb.start_soon(monitor(dut)) #concurrently 하게 monitor함수 실행.

    # We are reusing reset() from the previous example.
    await reset(dut)

    for _ in range(50000):
        await random_generate(dut)

'''
테스트 결과 정리
일단 어느정도 제대로 작동하는것을 확인하기는 했음
입력을 UQ16.16 고정소수점으로 설정하고 Newton-Raphson은 아직 구현되지 않아서 활성화시키지 않았음.

// 2. 출력 포맷 파라미터 (Unsigned)
    parameter OUTPUT_WIDTH      = 18, // 출력 역수 비트 수. 무조건 18 이상이어야 함!!!
    parameter OUT_INTEGER_BITS  = 0,  // 출력 정수부 비트 수 (보통 0~1)
    parameter OUT_FRAC_BITS     = 18, // 출력 소수부 비트 수 (OUT_INTEGER_BITS + OUT_FRAC_BITS == OUTPUT_WIDTH)

이렇게 설정하니까 입력을 완전 랜덤 32비트값으로 주고 10000번 돌렸을때 최대오차는 약 19%가 나왔음. 입력값이 너무 크면, 즉 정수부값이 너무 크면 그 역수는
대부분이 0이고 LSB몇개만 남아서, 마지막에 쉬프트되는 과정에서 다 잘려서 그런듯 함.

// 2. 출력 포맷 파라미터 (Unsigned)
    parameter OUTPUT_WIDTH      = 25, // 출력 역수 비트 수. 무조건 18 이상이어야 함!!!
    parameter OUT_INTEGER_BITS  = 0,  // 출력 정수부 비트 수 (보통 0~1)
    parameter OUT_FRAC_BITS     = 25, // 출력 소수부 비트 수 (OUT_INTEGER_BITS + OUT_FRAC_BITS == OUTPUT_WIDTH)

이렇게 출력을 UQ0.25로 설정하고 10000번 돌리니까 최대오차는 약 0.19% 정도가 나왔음. 입력값이 클때 역수는 매우 작은 수인데 25비트로 늘리니까 쉬프트할때 값이 
꽤 남아있어서 그런듯 함. +) 10만번 돌렸을때 최대오차 0.190945%임.

그런데 문제가 a = random.randint(1, (2**16)) #UQ16.16에서 정수부가 0인 소수부값이 들어갈때. 이렇게 값을 설정했을 때임.
입력이 1보다 작으니까 역수값이 너무 커지고 현재 OUT_INTEFER_BITS에는 비트를 거의 할당하지가 않아서 오버플로가 나서 오차가 96%이렇게 나왔음.
그래서
    // 2. 출력 포맷 파라미터 (Unsigned)
    parameter OUTPUT_WIDTH      = 25, // 출력 역수 비트 수. 무조건 18 이상이어야 함!!!
    parameter OUT_INTEGER_BITS  = 7,  // 출력 정수부 비트 수 (보통 0~1)
    parameter OUT_FRAC_BITS     = 18, // 출력 소수부 비트 수 (OUT_INTEGER_BITS + OUT_FRAC_BITS == OUTPUT_WIDTH)

이런식으로 출력의 정수부를 7비트 할당해주니까 괜찮아보이다가 이상적인 역수 값이 132.663968 이러니까 오차율이 96%이상 나옴. 이상적인 역수값이 19.145779 이런
경우에는 오차가 0.000139% 이렇게 나와서 정수부에 7비트를 할당했기 때문에 이상적인 정수값이 128을 넘어가는 즉시 오류가 나오는듯 함.

그래서 이 모듈 사용할떄 무조건 1보다 큰 수를 input으로 넣는다거나, 아니면 input으로 무조건 1보다 작은 소수점만 넣게 강제하는 등의 조건이 필요할 듯. Z값 1보다
작으면 싹다 culling 하고 1보다 큰것만 역수로 변환해서 나눗셈을 한다던지, 이렇게 해야할듯.

--------------------------------------------------------------------------------------------------------------------------------------------------
* 출력값을 18비트로 설정하고(UQ0.18), 입력값(UQ16.16) Z가 1 < Z < 128으로 설정하고 10만번 돌리니 최대오차는 약 0.05%정도 나옴. 
* 출력값을 18비트로 설정하고(UQ0.18), 입력값(UQ16.16) Z가 1 < Z < 256으로 설정하고 10만번 돌리니 최대오차는 약 0.10%정도 나옴. 
* 출력값을 18비트로 설정하고(UQ0.18), 입력값(UQ16.16) Z가 1 < Z < 512으로 설정하고 10만번 돌리니 최대오차는 약 0.19%정도 나옴.
* 출력값을 25비트로 설정하고(UQ0.25), 입력값(UQ16.16) Z가 1 < Z < 256으로 설정하고 10만번 돌리니 최대오차는 약 0.05%정도 나옴. 
* 출력값을 25비트로 설정하고(UQ0.25), 입력값(UQ16.16) Z가 1 < Z < 512으로 설정하고 10만번 돌리니 최대오차는 약 0.05%정도 나옴. 

즉 X/Z, Y/Z 계산할때 결국에 18bit x 25bit인 DSP에 맞춰야 함. 
* 1/Z에 18비트를 할당하고 X,Y에 25비트를 할당한다면 Z의 최대값을 128이나 256으로 설정해야 1/Z 오차가 0.1% 이하임.
* 1/Z에 25비트를 할당하고 X,Y에 18비트를 할당한다면 Z의 최대값을 256이나 512등으로 설정해도 1/Z 오차가 0.05% 이하임.

<Z: 25비트, X: 18비트> 최종 X/Z는 SQ2.14로 저장됨. 이후 (X/Z * 320) + 320 해서 SQ11.4로 변환됨
* 1 < Z < 128이고 -1 < X/Z < 1, 즉 -128 < X < 128 일때: X는 SQ7.10, 5만번 돌렸을때 X/Z 최대오차: 
* 1 < Z < 128이고 -2 < X/Z < 2, 즉 -256 < X < 256 일때: X는 SQ8.9, 5만번 돌렸을때 X/Z 최대오차:  
* 1 < Z < 256이고 -1 < X/Z < 1, 즉 -256 < X < 256 일때: X는 SQ8.9, 5만번 돌렸을때 X/Z 최대오차:  
* 1 < Z < 256이고 -2 < X/Z < 2, 즉 -512 < X < 512 일때: X는 SQ9.8, 5만번 돌렸을때 X/Z 최대오차:  
* 1 < Z < 512이고 -1 < X/Z < 1, 즉 -512 < X < 512 일때: X는 SQ9.8, 5만번 돌렸을때 X/Z 최대오차:  
* 1 < Z < 512이고 -2 < X/Z < 2, 즉 -1024 < X < 1024 일때: X는 SQ10.7, 5만번 돌렸을때 X/Z 최대오차:  

<Z: 18비트, X: 25비트> 최종 X/Z는 SQ2.14로 저장됨. 이후 (X/Z * 320) + 320 해서 SQ11.4로 변환됨
* 1 < Z < 128이고 -1 < X/Z < 1, 즉 -128 < X < 128 일때: X는 SQ7.17, 5만번 돌렸을때 X/Z 최대오차:  
* 1 < Z < 128이고 -2 < X/Z < 2, 즉 -256 < X < 256 일때: X는 SQ8.16, 5만번 돌렸을때 X/Z 최대오차:  
* 1 < Z < 256이고 -1 < X/Z < 1, 즉 -256 < X < 256 일때: X는 SQ8.16, 5만번 돌렸을때 X/Z 최대오차:  
* 1 < Z < 256이고 -2 < X/Z < 2, 즉 -512 < X < 512 일때: X는 SQ9.15, 5만번 돌렸을때 X/Z 최대오차:  
* 1 < Z < 512이고 -1 < X/Z < 1, 즉 -512 < X < 512 일때: X는 SQ9.15, 5만번 돌렸을때 X/Z 최대오차:  
* 1 < Z < 512이고 -2 < X/Z < 2, 즉 -1024 < X < 1024 일때: X는 SQ10.14, 5만번 돌렸을때 X/Z 최대오차:  

'''

