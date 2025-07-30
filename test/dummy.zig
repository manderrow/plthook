const std = @import("std");

export fn strtod_cust(str: [*:0]const u8) f64 {
    return std.fmt.parseFloat(f64, std.mem.span(str)) catch 0.0;
}
