const builtin = @import("builtin");
const std = @import("std");

const lib = @cImport({
    @cInclude("test/libtest.h");
});

const OpenMode = enum(c_int) {
    open,
    open_by_handle,
    open_by_address,
};

extern fn hook_function_calls_in_executable(open_mode: OpenMode) void;
extern fn hook_function_calls_in_library(open_mode: OpenMode, filename: [*:0]const u8) void;

fn showUsage() noreturn {
    std.debug.print("Usage: testprog (open | open_by_handle | open_by_address) LIB_NAME\n", .{});
    std.process.exit(1);
}

extern fn strtod(str: [*:0]const u8, ?*[*:0]const u8) f64;

extern fn reset_result() void;
extern fn check_result(str: [*:0]const u8, result: f64, expected_result: f64, line: c_long) void;

fn CHK_RESULT(comptime func: fn (str: [*:0]const u8) callconv(.c) f64, str: [:0]const u8, expected_result: f64, src: std.builtin.SourceLocation) void {
    reset_result();
    const result__ = func(str);
    check_result(str, result__, expected_result, @intCast(src.line));
}

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    var args = try std.process.argsWithAllocator(gpa);
    _ = args.next() orelse showUsage();
    const open_mode = std.meta.stringToEnum(OpenMode, args.next() orelse showUsage()) orelse showUsage();
    const filename = args.next() orelse showUsage();
    if (args.next()) |_| showUsage();

    const expected_result = strtod("3.7", null);

    // Resolve the function addresses by lazy binding.
    _ = lib.strtod_cdecl("3.7");
    if (builtin.os.tag == .windows) {
        _ = lib.strtod_stdcall("3.7");
        _ = lib.strtod_fastcall("3.7");
        _ = lib.strtod_export_by_ordinal("3.7");
    }

    hook_function_calls_in_executable(open_mode);
    hook_function_calls_in_library(open_mode, filename);

    CHK_RESULT(lib.strtod_cdecl, "3.7", expected_result, @src());
    if (builtin.os.tag == .windows) {
        CHK_RESULT(lib.strtod_stdcall, "3.7", expected_result, @src());
        CHK_RESULT(lib.strtod_fastcall, "3.7", expected_result, @src());
        CHK_RESULT(lib.strtod_export_by_ordinal, "3.7", expected_result, @src());
    }

    std.debug.print("success\n", .{});
}
