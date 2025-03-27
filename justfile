build-and-test: build test

build optimize="ReleaseFast":
	zig build -Doptimize={{optimize}} -Dtarget=x86_64-linux-gnu
	zig build -Doptimize={{optimize}} -Dtarget=x86_64-macos
	zig build -Doptimize={{optimize}} -Dtarget=x86_64-windows

test:
	zig build test -Doptimize=Debug

