# 1. 사용할 시뮬레이터 (기본: icarus / verilator 쓰려면 verilator)
SIM = icarus
TOPLEVEL_LANG = verilog

# 2. RTL 소스 파일 (상대 경로 또는 절대 경로)
VERILOG_SOURCES += $(PWD)/src/reciprocal_maker.v
VERILOG_SOURCES += $(PWD)/src/priority_encoder.v
VERILOG_SOURCES += $(PWD)/src/generic_bram.v


# 3. Verilog 최상위 모듈 이름 (module <이름> 에 들어간 이름)
TOPLEVEL = reciprocal_maker

# 4-1. 파이썬 모듈 검색 경로에 tb 폴더 추가
export PYTHONPATH := $(PWD)/tb:$(PYTHONPATH)

# 4. 실행할 파이썬 테스트 파일 이름 (.py 제외)
MODULE = reciprocal_maker_tb

# Enable waveform generation.
WAVES = 0

# 5. cocotb가 시스템/가상환경 경로에서 자동으로 읽어오도록 하는 마법의 한 줄
include $(shell cocotb-config --makefiles)/Makefile.sim