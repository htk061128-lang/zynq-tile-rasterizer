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

async def reset(dut):
    await RisingEdge(dut.clk)
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

def golden_model(indata, outdata):
    if indata == 0: return 444
    real_indata = indata / (2**16) #소수점이 16비트인 고정소수점값을 소수점 변환.
    real_outdata = outdata / (2**25) #output의 소수점 비트수만큼으로 나눠야 함!!!! 
    a = 1 / real_indata
    b = abs(((a - real_outdata) / a)) * 100 #절댓값이라서 양수로 나옴.
    return b, real_outdata, a #는 참값과의 오차율을 나타냄. %단위임.

async def random_generate_32(dut): #32비트 16비트 고정소수점 랜덤값 생성.
    a = random.randint(1, 2**32 - 1) #32비트 정수를 랜덤으로 뽑음.
    #a = random.randint(1, (2**8) * (2**16)) #Z로 나눌때 Z값의 최대가 256일때 어떻게 되는지 확인용.
    #a = random.randint(1, (2**16)) #UQ16.16에서 정수부가 0인 소수부값이 들어갈때
    await golden_queue.put(a) #큐에 a를 넣음.

    await RisingEdge(dut.clk)
    dut.in_data_a.value = a #랜덤 값 넣어줌
    dut.in_valid_a.value = 1

async def monitor(dut, count=100000):
    checked_count = 0
    big_error_rate = 0
    while checked_count < count:
        await RisingEdge(dut.clk)
        await Timer(1, "ns") # 엣지 직후 안정된 값 관찰

        if dut.out_valid_a.value == 1:
            in_val = await golden_queue.get() #큐에서 in_data_a값을 빼옴.
            error_rate, real, ideal = golden_model(in_val, int(dut.out_data_a.value))
            cocotb.log.info("checked_count: %d, 오차는 %f%%, 출력값: %f, 이상적인값: %f, 최고오차: %f", checked_count, error_rate, real, ideal, big_error_rate)
            if error_rate > big_error_rate: big_error_rate = error_rate
            assert big_error_rate < 90#, cocotb.log.error("오차 폭증! in_val (raw): 0x%X, in_val (float): %f, dut_out: 0x%X", in_val, in_val / 65536.0, int(dut.out_data_a.value))
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

    for _ in range(100000):
        await random_generate_32(dut)

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

'''

