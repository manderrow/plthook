build-and-test optimize="ReleaseFast": (build-no-args optimize) test

build-no-args optimize="ReleaseFast": (build "-Doptimize="+optimize)

build *ARGS:
	zig build {{ARGS}} -Dtarget=x86_64-linux-gnu
	zig build {{ARGS}} -Dtarget=x86_64-macos
	zig build {{ARGS}} -Dtarget=x86_64-windows

test:
	zig build test

