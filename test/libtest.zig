const builtin = @import("builtin");
const std = @import("std");

extern fn strtod(str: [*:0]const u8, ?*[*:0]const u8) f64;

fn strtod_cust(str: [*:0]const u8) f64 {
    return strtod(str, null);
}

export fn strtod_cdecl(str: [*:0]const u8) f64 {
    return strtod_cust(str);
}

const windows = if (builtin.os.tag == .windows) struct {
    export fn strtod_stdcall(str: [*:0]const u8) callconv(.winapi) f64 {
        return strtod_cust(str);
    }

    export fn strtod_fastcall(str: [*:0]const u8) callconv(if (builtin.target.cpu.arch == .x86) .x86_fastcall else .c) f64 {
        return strtod_cust(str);
    }
};

const darwin = if (builtin.os.tag.isDarwin()) struct {
    export fn atoi_dummy(str: [*:0]const u8) i32 {
        // Just to avoid to put "strtod" at the beginning of GOT.
        return std.fmt.parseInt(i32, std.mem.span(str), 10) catch @panic("invalid int");
    }
};

comptime {
    _ = windows;
    _ = darwin;
}
