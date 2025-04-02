const std = @import("std");

const logger = @import("logger.zig").logger;

pub const HandleByNameContext = struct {
    find_name: []const u8,
    result: usize = undefined,

    pub fn process(info: *std.posix.dl_phdr_info, size: usize, ctx: *HandleByNameContext) error{Done}!void {
        _ = size;

        if (info.name) |name| {
            if (std.mem.endsWith(u8, std.mem.span(name), ctx.find_name) != null) {
                logger.debug("found image \"{s}\" matching \"{s}\"", .{ name, ctx.find_name });
                ctx.result = info.addr;
                return error.Done;
            }
        }
    }
};
