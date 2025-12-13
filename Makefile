# Build configuration
BUILD_DIR        ?= build
INC_DIR          := include

TARGET_AMD64     ?= mini-init-amd64
TARGET_ARM64     ?= mini-init-arm64

AMD64_SRC_DIR    := src/amd64
ARM64_SRC_DIR    := src/arm64

NASM             := nasm
LD               := ld
NASMFLAGS        := -f elf64 -I$(INC_DIR)/ -g -F dwarf
LDFLAGS          := -nostdlib -z noexecstack

ARM64_AS         ?= aarch64-linux-gnu-as
ARM64_LD         ?= aarch64-linux-gnu-ld
ARM64_ASFLAGS    ?= -g
ARM64_LDFLAGS    ?= -nostdlib -z noexecstack

AMD64_BUILD_DIR  := $(BUILD_DIR)/amd64
ARM64_BUILD_DIR  := $(BUILD_DIR)/arm64

AMD64_SRCS       := main.asm signals.asm spawn.asm forward.asm wait.asm epoll.asm timer.asm log.asm time.asm
AMD64_OBJS       := $(addprefix $(AMD64_BUILD_DIR)/,$(AMD64_SRCS:.asm=.o))

ARM64_SRCS       := main.S signals.S spawn.S forward.S wait.S epoll.S timer.S log.S time.S util.S
ARM64_OBJS       := $(addprefix $(ARM64_BUILD_DIR)/,$(ARM64_SRCS:.S=.o))

.PHONY: helper-arm64
ARM64_HELPERS_SRCS := helpers/exit42.S helpers/sleeper.S
ARM64_HELPERS_OBJS := $(addprefix $(ARM64_BUILD_DIR)/,$(ARM64_HELPERS_SRCS:.S=.o))
ARM64_HELPERS_BINS := $(ARM64_BUILD_DIR)/helper-exit42 $(ARM64_BUILD_DIR)/helper-sleeper

.PHONY: all all-amd64 build-arm64 clean test test-amd64 test-arm64 test-all

all: all-amd64

all-amd64: $(BUILD_DIR)/$(TARGET_AMD64)

build-arm64: $(BUILD_DIR)/$(TARGET_ARM64) $(ARM64_HELPERS_BINS)

build-amd64: $(BUILD_DIR)/$(TARGET_AMD64)

test: test-amd64

test-amd64: $(BUILD_DIR)/$(TARGET_AMD64)
	bash scripts/test_harness.sh $(BUILD_DIR)/$(TARGET_AMD64)

test-arm64: $(BUILD_DIR)/$(TARGET_ARM64)
	bash scripts/test_harness_arm64.sh $(BUILD_DIR)/$(TARGET_ARM64)

test-all: test-amd64
	bash scripts/test_ep_signals.sh $(BUILD_DIR)/$(TARGET_AMD64)
	bash scripts/test_edge_cases.sh $(BUILD_DIR)/$(TARGET_AMD64)
	bash scripts/test_exit_code_mapping.sh $(BUILD_DIR)/$(TARGET_AMD64)
	bash scripts/test_restart.sh $(BUILD_DIR)/$(TARGET_AMD64)
	bash scripts/test_diagnostics.sh $(BUILD_DIR)/$(TARGET_AMD64)

$(AMD64_BUILD_DIR):
	mkdir -p $@

$(ARM64_BUILD_DIR):
	mkdir -p $@

$(AMD64_BUILD_DIR)/%.o: $(AMD64_SRC_DIR)/%.asm | $(AMD64_BUILD_DIR)
	$(NASM) $(NASMFLAGS) $< -o $@

$(ARM64_BUILD_DIR)/%.o: $(ARM64_SRC_DIR)/%.S | $(ARM64_BUILD_DIR)
	$(ARM64_AS) $(ARM64_ASFLAGS) -I$(INC_DIR) $< -o $@

# Helper objects
$(ARM64_BUILD_DIR)/helpers/%.o: $(ARM64_SRC_DIR)/helpers/%.S | $(ARM64_BUILD_DIR)
	mkdir -p $(ARM64_BUILD_DIR)/helpers
	$(ARM64_AS) $(ARM64_ASFLAGS) -I$(INC_DIR) $< -o $@

$(BUILD_DIR)/$(TARGET_AMD64): $(AMD64_OBJS)
	$(LD) $(LDFLAGS) -o $@ $(AMD64_OBJS)

$(BUILD_DIR)/$(TARGET_ARM64): $(ARM64_OBJS)
	$(ARM64_LD) $(ARM64_LDFLAGS) -o $@ $(ARM64_OBJS)

# Helper binaries (linked standalone)
$(ARM64_BUILD_DIR)/helper-exit42: $(ARM64_BUILD_DIR)/helpers/exit42.o
	$(ARM64_LD) $(ARM64_LDFLAGS) -o $@ $<

$(ARM64_BUILD_DIR)/helper-sleeper: $(ARM64_BUILD_DIR)/helpers/sleeper.o
	$(ARM64_LD) $(ARM64_LDFLAGS) -o $@ $<

clean:
	rm -rf $(BUILD_DIR)
