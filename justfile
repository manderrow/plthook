build-and-test: build test

build-no-args optimize="ReleaseFast":
	build -Doptimize={{optimize}}

build *ARGS:
	zig build {{ARGS}} -Dtarget=x86_64-linux-gnu
	zig build {{ARGS}} -Dtarget=x86_64-macos
	zig build {{ARGS}} -Dtarget=x86_64-windows

test:
	zig build test

