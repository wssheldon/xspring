.PHONY: all clean xsummer yclient

all: xsummer yclient

xsummer:
	cd xsummer && zig build

yclient:
	cd yclient && cargo build

clean:
	cd xsummer && rm -rf .zig-cache/ && rm -rf .cache/
	cd yclient && cargo clean
	rm -rf **/target **/zig-out **/zig-cache
