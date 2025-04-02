const std = @import("std");

const root = @import("root.zig");
const c = root.c;
const internal = @cImport(@cInclude("plthook_osx_internal.h"));

const logger = @import("logger.zig").logger;

const dyld = @cImport(@cInclude("mach-o/dyld.h"));

pub fn open(image_idx: u32, mh: ?*const dyld.mach_header, image_name: ?[*:0]const u8) root.Error!*c.plthook_t {
    var plthook_out: ?*internal.plthook_t = undefined;
    return switch (@as(root.Result, @enumFromInt(internal.plthook_open_real(
        &plthook_out,
        image_idx,
        // need to cast from dyld._ to internal._
        @ptrCast(mh),
        image_name,
    )))) {
        // need to cast from internal._ to c._
        .Success => @ptrCast(plthook_out.?),
        inline else => |tag| @field(root.Error, @tagName(tag)),
    };
}

pub fn getImageByFilename(name_ptr: [*:0]const u8) ?struct { idx: u32, name: [:0]const u8 } {
    const name = std.mem.span(name_ptr);
    for (1..std.c._dyld_image_count()) |idx| {
        const image_name = std.mem.span(std.c._dyld_get_image_name(@intCast(idx)));
        if (std.mem.endsWith(u8, image_name, name)) {
            logger.debug("found image \"{s}\" matching \"{s}\"", .{ image_name, name });
            return .{ .idx = @intCast(idx), .name = image_name };
        }
    }
    return null;
}

pub fn handleByFilename(name_ptr: [*:0]const u8) ?*anyopaque {
    const info = getImageByFilename(name_ptr) orelse return null;
    return std.c.dlopen(info.name, .{ .LAZY = true, .NOLOAD = true });
}
