# Builds every compiled implementation that exists. Missing sources are simply
# not built, so the tree works at any stage of the port.
#
# C and C++ are built twice, once per compiler, and reported separately.

CFLAGS  := -O3 -march=native -flto -fno-plt -fomit-frame-pointer -pthread
CXXFLAGS:= $(CFLAGS) -std=c++20
LDFLAGS := -flto -pthread

C_SRC   := $(wildcard impl/c/*.c)
CPP_SRC := $(wildcard impl/cpp/*.cpp)
GO_SRC  := $(wildcard impl/go/*.go)
ASM_SRC := $(wildcard impl/asm/*.asm)

C_ALGOS   := $(notdir $(basename $(C_SRC)))
CPP_ALGOS := $(notdir $(basename $(CPP_SRC)))
GO_ALGOS  := $(notdir $(basename $(GO_SRC)))
ASM_ALGOS := $(notdir $(basename $(ASM_SRC)))

TARGETS := \
  $(addprefix build/c-gcc-,$(C_ALGOS)) \
  $(addprefix build/c-clang-,$(C_ALGOS)) \
  $(addprefix build/cpp-gcc-,$(CPP_ALGOS)) \
  $(addprefix build/cpp-clang-,$(CPP_ALGOS)) \
  $(addprefix build/go-,$(GO_ALGOS)) \
  $(addprefix build/asm-,$(ASM_ALGOS))

ifneq ($(wildcard impl/rust/Cargo.toml),)
RUST_ALGOS := $(notdir $(basename $(wildcard impl/rust/src/bin/*.rs)))
TARGETS += $(addprefix build/rust-,$(RUST_ALGOS))
endif

.PHONY: all clean
all: $(TARGETS)

build:
	@mkdir -p build

build/c-gcc-%: impl/c/%.c | build
	gcc $(CFLAGS) $< -o $@ $(LDFLAGS)

build/c-clang-%: impl/c/%.c | build
	clang $(CFLAGS) $< -o $@ $(LDFLAGS)

build/cpp-gcc-%: impl/cpp/%.cpp | build
	g++ $(CXXFLAGS) $< -o $@ $(LDFLAGS)

build/cpp-clang-%: impl/cpp/%.cpp | build
	clang++ $(CXXFLAGS) $< -o $@ $(LDFLAGS)

build/go-%: impl/go/%.go | build
	go build -o $@ $<

build/asm-%: impl/asm/%.asm | build
	nasm -f elf64 -O3 $< -o build/$*.o
	gcc -no-pie -pthread build/$*.o -o $@

build/rust-%: impl/rust/src/bin/%.rs impl/rust/Cargo.toml | build
	cd impl/rust && RUSTFLAGS="-C target-cpu=native" cargo build --release --bin $* -q
	cp impl/rust/target/release/$* $@

clean:
	rm -rf build impl/rust/target
