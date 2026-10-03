#!/usr/bin/env python3

ENTRIES = 2048       # 2048개 주소 (0 ~ 2047, 소수부 11비트)
DATA_WIDTH = 18      # 18-bit (UQ0.18)
MAX_VAL = (1 << DATA_WIDTH) - 1  # 0x3FFFF (262143)

filename = "reciprocal_18x2048.hex"

with open(filename, "w") as f:
    for i in range(ENTRIES):
        # 1.0 <= real_x < 2.0 (정수부 1.0 + 소수부 i / 2048)
        real_x = 1.0 + (i / ENTRIES)
        
        # 실제 이상적인 역수 참값 (0.5 < reciprocal <= 1.0)
        reciprocal = 1.0 / real_x
        
        # UQ0.18 스케일링: 2^18을 곱해 정수로 양자화
        raw_val = int(round(reciprocal * (1 << DATA_WIDTH)))
        
        # 1.0일 때 2^18(0x40000)이 되어 18비트를 1 LSB 초과하므로 MAX_VAL(0x3FFFF)로 클램핑
        val = min(raw_val, MAX_VAL)

        f.write(f"{val:05X}\n")

print(f"생성 완료: {filename} ({ENTRIES} lines, UQ0.18 18-bit hex)")