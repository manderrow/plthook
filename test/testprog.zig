const builtin = @import("builtin");
const std = @import("std");

const plthook = @import("plthook");

const lib = struct {
    extern fn strtod_cdecl(str: [*:0]const u8) f64;

    extern fn strtod_stdcall(str: [*:0]const u8) callconv(.winapi) f64;
    extern fn strtod_fastcall(str: [*:0]const u8) callconv(.{ .x86_fastcall = .{} }) f64;
    extern fn strtod_export_by_ordinal(str: [*:0]const u8) f64;
};

const OpenMode = enum(c_int) {
    open,
    open_by_handle,
    open_by_address,
};

fn showUsage() noreturn {
    std.debug.print("Usage: testprog (open | open_by_handle | open_by_address) LIB_NAME\n", .{});
    std.process.exit(1);
}

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

var strtod_cdecl_old_func: ?*const fn ([*:0]const u8) callconv(.c) f64 = null;

/// hook func from libtest to libc.
fn strtod_hook_func(str: [*:0]const u8) callconv(.c) f64 {
    const result = std.fmt.parseFloat(f64, std.mem.span(str)) catch 0.0;
    setResult(&val_lib2libc, str, result);
    return result;
}

/// hook func from testprog to libtest.
fn strtod_cdecl_hook_func(str: [*:0]const u8) callconv(.c) f64 {
    const result = strtod_cdecl_old_func.?(str);
    setResult(&val_exe2lib, str, result);
    return result;
}

const windows = if (builtin.os.tag == .windows) struct {
    const supports_ordinal_export = false;

    var strtod_stdcall_old_func: ?*const fn ([*:0]const u8) callconv(.winapi) f64 = null;

    /// hook func from testprog to libtest.
    fn strtod_stdcall_hook_func(str: [*:0]const u8) callconv(.winapi) f64 {
        const result = strtod_stdcall_old_func.?(str);
        setResult(&val_exe2lib, str, result);
        return result;
    }

    const x86 = if (builtin.cpu.arch == .x86) struct {
        var strtod_fastcall_old_func: ?*const fn ([*:0]const u8) callconv(.{ .x86_fastcall = .{} }) f64 = null;

        /// hook func from testprog to libtest.
        fn strtod_fastcall_hook_func(str: [*:0]const u8) callconv(.{ .x86_fastcall = .{} }) f64 {
            const result = strtod_fastcall_old_func.?(str);
            setResult(&val_exe2lib, str, result);
            return result;
        }
    };

    var strtod_export_by_ordinal_old_func: ?*const fn ([*:0]const u8) callconv(.c) f64 = if (!supports_ordinal_export) @compileError("ordinal export not supported") else null;

    /// hook func from testprog to libtest.
    fn strtod_export_by_ordinal_hook_func(str: [*:0]const u8) callconv(.c) f64 {
        if (!supports_ordinal_export) @compileError("ordinal export not supported");
        const result = strtod_export_by_ordinal_old_func.?(str);
        setResult(&val_exe2lib, str, result);
        return result;
    }
};

const EnumTestData = struct {
    name: [:0]const u8,
    enumerated: bool = false,
};

const funcs_called_by_libtest: []const EnumTestData = &.{
    if (builtin.os.tag.isDarwin()) switch (builtin.target.ptrBitWidth()) {
        32 => .{ .name = "_strtod_cust$UNIX2003" },
        64 => .{ .name = "_strtod_cust" },
        else => @compileError("Unsupported ptrBitWidth"),
    } else .{ .name = "strtod_cust" },
};

const funcs_called_by_main: []const EnumTestData = &if (builtin.os.tag == .windows and builtin.target.ptrBitWidth() == 64) .{
    .{ .name = "strtod_cdecl" },
    .{ .name = "strtod_stdcall" },
    // TODO: maybe support this
    //.{ .name = "libtest.dll:@10" },
} else if (builtin.os.tag == .windows and builtin.abi.isGnu()) .{
    .{ .name = "strtod_cdecl" },
    .{ .name = "strtod_stdcall@8" },
    .{ .name = "@strtod_fastcall@8" },
} else if (builtin.os.tag == .windows) .{
    .{ .name = "strtod_cdecl" },
    .{ .name = "_strtod_stdcall@8" },
    .{ .name = "@strtod_fastcall@8" },
    //.{ .name = "libtest.dll:@10" },
} else if (builtin.os.tag.isDarwin()) .{
    .{ .name = "_strtod_cdecl" },
} else .{
    .{ .name = "strtod_cdecl" },
};

fn test_plthook_enum(instance: *plthook.c.plthook_t, test_data: []EnumTestData) !void {
    var pos: c_uint = 0;
    var name: [*:0]const u8 = undefined;
    var addr: *?*anyopaque = undefined;

    var enumerated: usize = 0;

    while (plthook.c.plthook_enum(instance, &pos, @ptrCast(&name), @ptrCast(&addr)) == 0) {
        for (test_data) |*e| {
            if (std.mem.eql(u8, e.name, std.mem.span(name))) {
                e.enumerated = true;
                enumerated += 1;
                break;
            }
        }
    }

    if (enumerated != test_data.len) {
        for (test_data) |e| {
            if (!e.enumerated) {
                std.debug.print("{s} is not enumerated by plthook_enum.\n", .{e.name});
            }
        }
        pos = 0;
        while (plthook.c.plthook_enum(instance, &pos, @ptrCast(&name), @ptrCast(&addr)) == 0) {
            std.debug.print("   {s}\n", .{name});
        }
        return error.TestUnexpectedResult;
    }
}

fn hook_function_calls_in_executable(open_mode: OpenMode) !void {
    std.debug.print("opening executable via {}\n", .{open_mode});
    const instance = switch (open_mode) {
        .open => try plthook.openByName(null),
        .open_by_handle => blk: {
            const handle = switch (builtin.os.tag) {
                .windows => std.os.windows.kernel32.GetModuleHandleW(null).?,
                else => std.c.dlopen(null, .{ .LAZY = true }).?,
            };
            break :blk try plthook.openByHandle(handle);
        },
        .open_by_address => try plthook.openByAddress(@intFromPtr(&hook_function_calls_in_executable)),
    };
    var test_data = funcs_called_by_main[0..funcs_called_by_main.len].*;
    try test_plthook_enum(instance, &test_data);
    strtod_cdecl_old_func = try plthook.replace(instance, "strtod_cdecl", &strtod_cdecl_hook_func);
    if (builtin.os.tag == .windows) {
        windows.strtod_stdcall_old_func = try plthook.replace(instance, "strtod_stdcall", &windows.strtod_stdcall_hook_func);
        if (builtin.cpu.arch == .x86) {
            windows.x86.strtod_fastcall_old_func = try plthook.replace(instance, "strtod_fastcall", &windows.x86.strtod_fastcall_hook_func);
        }
        if (windows.supports_ordinal_export) {
            windows.strtod_export_by_ordinal_old_func = try plthook.replace(instance, "libtest.dll:@10", &windows.strtod_export_by_ordinal_hook_func);
        }
    }
    plthook.c.plthook_close(instance);
}

fn hook_function_calls_in_library(open_mode: OpenMode, filename: [:0]const u8) !void {
    std.debug.print("opening {s} via {}\n", .{ filename, open_mode });
    const instance = switch (open_mode) {
        .open => try plthook.openByName(filename),
        .open_by_handle, .open_by_address => blk: {
            const handle = switch (builtin.os.tag) {
                .windows => handle: {
                    var buf: [127:0]u16 = undefined;
                    const n = try std.unicode.utf8ToUtf16Le(&buf, filename);
                    buf[n] = 0;
                    break :handle std.os.windows.kernel32.GetModuleHandleW(buf[0..n :0]).?;
                },
                else => std.c.dlopen(filename, .{ .LAZY = true, .NOLOAD = true }).?,
            };
            break :blk switch (open_mode) {
                .open => unreachable,
                .open_by_handle => try plthook.openByHandle(handle),
                .open_by_address => blk1: {
                    const address = switch (builtin.os.tag) {
                        .windows => handle,
                        else => std.c.dlsym(handle, "strtod_cdecl").?,
                    };
                    break :blk1 try plthook.openByAddress(@intFromPtr(address));
                },
            };
        },
    };
    var test_data = funcs_called_by_libtest[0..funcs_called_by_libtest.len].*;
    try test_plthook_enum(instance, &test_data);
    _ = try plthook.replace(instance, "strtod_cust", &strtod_hook_func);
    plthook.c.plthook_close(instance);
}

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    var args = try std.process.argsWithAllocator(gpa);
    _ = args.next() orelse showUsage();
    const open_mode = std.meta.stringToEnum(OpenMode, args.next() orelse showUsage()) orelse showUsage();
    const filename = args.next() orelse showUsage();
    if (args.next()) |_| showUsage();

    const expected_result = comptime std.fmt.parseFloat(f64, "3.7") catch unreachable;

    // Resolve the function addresses by lazy binding.
    _ = lib.strtod_cdecl("3.7");
    if (builtin.os.tag == .windows) {
        _ = lib.strtod_stdcall("3.7");
        if (builtin.cpu.arch == .x86) {
            _ = lib.strtod_fastcall("3.7");
        }
        if (windows.supports_ordinal_export) {
            _ = lib.strtod_export_by_ordinal("3.7");
        }
    }

    try hook_function_calls_in_executable(open_mode);
    try hook_function_calls_in_library(open_mode, filename);

    try testResult(lib.strtod_cdecl, "3.7", expected_result, @src());
    if (builtin.os.tag == .windows) {
        try testResult(lib.strtod_stdcall, "3.7", expected_result, @src());
        if (builtin.cpu.arch == .x86) {
            try testResult(lib.strtod_fastcall, "3.7", expected_result, @src());
        }
        if (windows.supports_ordinal_export) {
            try testResult(lib.strtod_export_by_ordinal, "3.7", expected_result, @src());
        }
    }

    std.debug.print("success\n", .{});
}
