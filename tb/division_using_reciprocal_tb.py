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

NUM_CHANNELS = 1 #분자(Numerator)의 개수(분모는 하나일때)
NUM_WIDTH = 25 #분자는 signed 값임.
NUM_FRAC = 16

DEN_WIDTH = 24 #분모(Denominator) 비트수
DEN_FRAC = 16 #분모는 unsigned 값임
IS_BIG_THAN_1 = 1

OUT_WIDTH = 48
OUT_FRAC = 24



input_queue = Queue() #입력값을 큐에 넣고 monitor가 하나씩 빼서 golden_queue와 비교함.
output_queue = Queue() #모듈의 출력값을 저장함.

# 2의 보수(음수)를 파이썬의 음수로 변환하는 헬퍼 함수
def to_signed(val, bits):
    if val >= (1 << (bits - 1)):  # 최상위 비트(MSB)가 1이면 음수
        val = val - (1 << bits) #MSB가 1이면 (1 << bits) = 2^bits 만큼 빼서 원래 MSB인 +2^(bits-1) 성분을 -2^(bits-1)성분으로 변환함.
    return val

async def reset(dut):
    await RisingEdge(dut.clk)
    dut.reset.value = 1
    await RisingEdge(dut.clk)
    dut.reset.value = 0
    await RisingEdge(dut.clk)

async def monitor(dut):
    while True:
        await RisingEdge(dut.clk)
        await Timer(1, "ns") # 엣지 직후 안정된 값 관찰
        if(dut.out_valid_a.value == 1):
            await output_queue.put((dut.out_quotients_a.value, dut.div_by_zero_a.value)) #출력을 output_queue에 넣음.

async def scoreboard(dut):
    max_error_rate = 0
    while True:
        quotients, div_by_zero = await output_queue.get()
        if NUM_CHANNELS == 2:
            mask = (1 << OUT_WIDTH) - 1
            raw_q1 = int(quotients) & mask #int() 함수는 unsigned로 값을 변환하므로 이걸 signed형으로 해석해야 함.
            raw_q2 = int(quotients) >> OUT_WIDTH
            quotients_1 = to_signed(raw_q1, OUT_WIDTH)
            quotients_2 = to_signed(raw_q2, OUT_WIDTH)
        elif NUM_CHANNELS == 1: 
            mask = (1 << OUT_WIDTH) - 1
            raw_q1 = int(quotients) & mask
            quotients_1 = to_signed(raw_q1, OUT_WIDTH)
            quotients_2 = 0 #사용 X

        numerator, denominator = await input_queue.get()
        if NUM_CHANNELS == 2:
            mask = (1 << OUT_WIDTH) - 1
            raw_n1 = int(numerator) & mask
            raw_n2 = int(numerator) >> OUT_WIDTH
            numerator_1 = to_signed(raw_n1, NUM_WIDTH) #MSB가 1이면 (1 << NUM_WIDTH) = 2^NUM_WIDTH 만큼 빼서 원래 MSB인 +2^(NUM_WIDTH-1) 성분을 -2^(NUM_WIDTH-1)성분으로 변환함.
            numerator_2 = to_signed(raw_n2, NUM_WIDTH)
        elif NUM_CHANNELS == 1: 
            mask = (1 << OUT_WIDTH) - 1
            raw_n1 = int(numerator) & mask
            numerator_1 = to_signed(raw_n1, NUM_WIDTH)
            numerator_2 = 0 #사용 X

        adjusted_numerator_1 = (numerator_1/(2**NUM_FRAC)) #분자 고정소수점 보정 
        adjusted_numerator_2 = (numerator_2/(2**NUM_FRAC)) #분자 고정소수점 보정 

        adjusted_denominator = (int(denominator)/(2**DEN_FRAC)) #분모는 unsigned값이므로 singed로 다시 해석하는 과정을 거칠 필요가 없음

        golden_value_1 = adjusted_numerator_1 / adjusted_denominator
        golden_value_2 = adjusted_numerator_2 / adjusted_denominator

        adjusted_quotients_1 = quotients_1 / (2**OUT_FRAC) #몫을 고정소수점 보정함.
        adjusted_quotients_2 = quotients_2 / (2**OUT_FRAC) #몫을 고정소수점 보정함.

        if NUM_CHANNELS == 2:
            error_rate_1 = abs((golden_value_1 - adjusted_quotients_1) / golden_value_1)
            error_rate_2 = abs((golden_value_2 - adjusted_quotients_2) / golden_value_2)
            if max_error_rate < error_rate_1: max_error_rate = error_rate_1
            if max_error_rate < error_rate_2: max_error_rate = error_rate_2 #채널이 2개이므로 2개 다 max_error_rate와 비교함.
            
            # 채널 2개일 때 출력
            cocotb.log.info(f"[CH1] Num: {adjusted_numerator_1:<5} | Den: {adjusted_denominator:<5} || "
                          f"Golden: {golden_value_1:9.6f} | HW: {adjusted_quotients_1:9.6f} | Err: {error_rate_1:7.6%}")
            cocotb.log.info(f"[CH2] Num: {adjusted_numerator_2:<5} | Den: {adjusted_denominator:<5} || "
                          f"Golden: {golden_value_2:9.6f} | HW: {adjusted_quotients_2:9.6f} | Err: {error_rate_2:7.6%}")
            cocotb.log.info(f">>> Current Max Error: {max_error_rate:.4%}")
            cocotb.log.info("-" * 80) # 로그 간 구분을 위한 줄 긋기 (선택 사항)

            assert (max_error_rate * 100) < 1

        elif NUM_CHANNELS == 1: 
            error_rate_1 = abs((golden_value_1 - adjusted_quotients_1) / golden_value_1)
            if max_error_rate < error_rate_1: max_error_rate = error_rate_1
            
            # 채널 1개일 때 출력
            cocotb.log.info(f"[CH1] Num: {adjusted_numerator_1:<5} | Den: {adjusted_denominator:<5} || "
                          f"Golden: {golden_value_1:9.6f} | HW: {adjusted_quotients_1:9.6f} | Err: {error_rate_1:7.6%}")
            cocotb.log.info(f">>> Current Max Error: {max_error_rate:.4%}")
            cocotb.log.info("-" * 80) # 로그 간 구분을 위한 줄 긋기 (선택 사항)

            assert (max_error_rate * 100) < 1
 
async def driver(dut):
    await RisingEdge(dut.clk)

    num_int_min = 0
    num_int_max = (1 << NUM_WIDTH) - 1
    num_val_1 = random.randint(num_int_min, num_int_max) #sined 값임
    num_val_2 = random.randint(num_int_min, num_int_max)

    if IS_BIG_THAN_1 == 1: #분모가 1보다 큰 unsigned 값일때
        den_int_min = (1 << DEN_FRAC)
        den_int_max = (1 << DEN_WIDTH) - 1
    elif IS_BIG_THAN_1 == 0: #분모가 1보다 작은 unsigned 값일때
        den_int_min = 1 #0으로 나누는건 일단은 고려하지 않음
        den_int_max = (1 << DEN_FRAC) - 1

    den_val = random.randint(den_int_min, den_int_max)

    if NUM_CHANNELS == 2:
        padding_num_val = (num_val_2 << NUM_WIDTH) + num_val_1
    elif NUM_CHANNELS == 1:
        padding_num_val = num_val_1 # 25비트만 사용

    dut.in_valid_a.value = 1
    dut.in_numerators_a.value = padding_num_val
    dut.in_denominator_a.value = den_val
    await input_queue.put((padding_num_val, den_val))
    


@cocotb.test
async def main_test(dut):
    # Start the clock running concurrently to the main test coroutine.
    Clock(dut.clk, 10, "ns").start()
    cocotb.start_soon(monitor(dut)) #concurrently 하게 monitor함수 실행.
    cocotb.start_soon(scoreboard(dut))

    # We are reusing reset() from the previous example.
    await reset(dut)

    cocotb.log.info("driver start!")
    for _ in range(100000):
        await driver(dut)