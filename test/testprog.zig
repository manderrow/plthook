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

const HookedVal = struct {
    str: [30:0]u8 = .{0} ** 30,
    result: f64 = 0.0,
};

/// value captured by hook from executable to libtest.
var val_exe2lib: HookedVal = .{};
/// value captured by hook from libtest to libc.
var val_lib2libc: HookedVal = .{};

fn setResult(hv: *HookedVal, str: [*:0]const u8, result: f64) void {
    const strs = std.mem.span(str);
    @memcpy(hv.str[0..strs.len], strs);
    hv.str[strs.len] = 0;
    hv.result = result;
}

fn expectResult(str: [:0]const u8, result: f64, expected_result: f64, line: u32) !void {
    errdefer {
        std.debug.print("Error: ['{s}', {}, {}] ['{s}', {}] ['{s}', {}] at line {}\n", .{ str, result, expected_result, val_exe2lib.str, val_exe2lib.result, val_lib2libc.str, val_lib2libc.result, line });
    }

    try std.testing.expectEqual(expected_result, result);
    try std.testing.expectEqualStrings(str, std.mem.span(@as([*:0]const u8, &val_exe2lib.str)));
    try std.testing.expectEqual(expected_result, val_exe2lib.result);
    try std.testing.expectEqualStrings(str, std.mem.span(@as([*:0]const u8, &val_lib2libc.str)));
    try std.testing.expectEqual(expected_result, val_lib2libc.result);
}

fn testResult(comptime func: fn (str: [*:0]const u8) callconv(.c) f64, str: [:0]const u8, expected_result: f64, src: std.builtin.SourceLocation) !void {
    val_exe2lib = .{};
    val_lib2libc = .{};
    const result__ = func(str);
    try expectResult(str, result__, expected_result, src.line);
}

export var strtod_cdecl_old_func: ?*const fn ([*:0]const u8) callconv(.c) f64 = null;

/// hook func from libtest to libc.
export fn strtod_hook_func(str: [*:0]const u8) f64 {
    const result = strtod(str, null);
    setResult(&val_lib2libc, str, result);
    return result;
}

/// hook func from testprog to libtest.
export fn strtod_cdecl_hook_func(str: [*:0]const u8) f64 {
    const result = strtod_cdecl_old_func.?(str);
    setResult(&val_exe2lib, str, result);
    return result;
}

comptime {
    if (builtin.os.tag == .windows) {
        if (builtin.cpu.arch == .x86) {
            _ = struct {
                export var strtod_stdcall_old_func: ?fn ([*:0]const u8) callconv(.{ .x86_stdcall = .{} }) f64 = null;
                export var strtod_fastcall_old_func: ?fn ([*:0]const u8) callconv(.{ .x86_fastcall = .{} }) f64 = null;

                /// hook func from testprog to libtest.
                export fn strtod_stdcall_hook_func(str: [*:0]const u8) callconv(.{ .x86_stdcall = .{} }) void {
                    const result = strtod_stdcall_old_func(str);
                    setResult(&val_exe2lib, str, result);
                    return result;
                }

                /// hook func from testprog to libtest.
                export fn strtod_fastcall_hook_func(str: [*:0]const u8) callconv(.{ .x86_fastcall = .{} }) void {
                    const result = strtod_fastcall_old_func(str);
                    setResult(&val_exe2lib, str, result);
                    return result;
                }
            };
        }
        _ = struct {
            export var strtod_export_by_ordinal_old_func: ?fn ([*:0]const u8) callconv(.c) f64 = null;

            /// hook func from testprog to libtest.
            export fn strtod_export_by_ordinal_hook_func(str: [*:0]const u8) void {
                const result = strtod_export_by_ordinal_old_func(str);
                setResult(&val_exe2lib, str, result);
                return result;
            }
        };
    }
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

    try testResult(lib.strtod_cdecl, "3.7", expected_result, @src());
    if (builtin.os.tag == .windows) {
        try testResult(lib.strtod_stdcall, "3.7", expected_result, @src());
        try testResult(lib.strtod_fastcall, "3.7", expected_result, @src());
        try testResult(lib.strtod_export_by_ordinal, "3.7", expected_result, @src());
    }

    std.debug.print("success\n", .{});
}
