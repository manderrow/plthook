const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.addModule("plthook", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .strip = true,
        .link_libc = true,
    });
    lib_mod.addIncludePath(b.path("."));
    lib_mod.addIncludePath(b.path("include"));

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

    const lib_test_prog_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
    });

    lib_test_prog_mod.addCSourceFiles(.{
        .files = &.{
            "test/testprog.c",
            "test/libtest.c",
        },
        .flags = &.{ "-Wall", "-Werror" },
    });
    lib_test_prog_mod.addIncludePath(b.path("."));

    lib_test_prog_mod.linkLibrary(lib);

    const lib_test_prog = b.addExecutable(.{
        .name = "plthook-test",
        .root_module = lib_test_prog_mod,
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    for ([_][]const u8{ "open", "open_by_handle", "open_by_address" }) |mode| {
        const run_lib_test_prog = b.addRunArtifact(lib_test_prog);
        run_lib_test_prog.addArg(mode);
        test_step.dependOn(&run_lib_test_prog.step);
    }
}
