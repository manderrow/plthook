const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const strip = b.option(bool, "strip", "Forces stripping on all optimization modes") orelse switch (optimize) {
        .Debug, .ReleaseSafe => false,
        .ReleaseFast, .ReleaseSmall => true,
    };

    const trace = b.option(bool, "trace", "Enables extremely verbose logging") orelse false;

    const lib_mod = b.addModule("plthook", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
        .link_libc = true,
    });
    lib_mod.addIncludePath(b.path("."));
    lib_mod.addIncludePath(b.path("include"));

    if (trace) {
        lib_mod.addCMacro("PLTHOOK_DEBUG_CMD", "1");
        lib_mod.addCMacro("PLTHOOK_DEBUG_BIND", "1");
        lib_mod.addCMacro("PLTHOOK_DEBUG_FIXUPS", "1");
        lib_mod.addCMacro("PLTHOOK_DEBUG_ADDR", "1");
    }

    lib_mod.addCSourceFile(.{
        .file = b.path(switch (target.result.os.tag) {
            .linux => "plthook_elf.c",
            .macos => "plthook_osx.c",
            .windows => "plthook_win32.c",
            else => return error.UnsupportedOS,
        }),
        .flags = &.{ "-Wall", "-Werror" },
    });

    switch (target.result.os.tag) {
        .macos => {
            lib_mod.addIncludePath(b.path("lib/include/osx"));
        },
        .windows => {
            lib_mod.linkSystemLibrary("Dbghelp", .{});
        },
        else => {},
    }

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "plthook",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);

    b.getInstallStep().dependOn(&b.addInstallHeaderFile(b.path("plthook.h"), "plthook.h").step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const lib_test_mod = b.createModule(.{
        .root_source_file = b.path("test/libtest.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_test = b.addLibrary(.{
        .name = "plthook-test",
        .root_module = lib_test_mod,
        .linkage = .dynamic,
    });

    const test_prog_mod = b.createModule(.{
        .root_source_file = b.path("test/testprog.zig"),
        .target = target,
        .optimize = optimize,
    });

    test_prog_mod.addImport("plthook", lib_mod);

    test_prog_mod.addIncludePath(b.path("."));

    test_prog_mod.linkLibrary(lib_test);

    const test_prog = b.addExecutable(.{
        .name = "plthook-testprog",
        .root_module = test_prog_mod,
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    test_step.dependOn(&b.addInstallArtifact(test_prog, .{}).step);

    for ([_][]const u8{ "open", "open_by_handle", "open_by_address" }) |mode| {
        const run_lib_test_prog = b.addRunArtifact(test_prog);
        run_lib_test_prog.addArg(mode);
        run_lib_test_prog.addArg(lib_test.out_filename);
        test_step.dependOn(&run_lib_test_prog.step);
    }
}
