const lib = @import("root.zig");
const c = lib.c;
const internal = @cImport(@cInclude("plthook_osx_internal.h"));

const dyld = @cImport(@cInclude("mach-o/dyld.h"));

pub fn open(image_idx: u32, mh: ?*const dyld.mach_header, image_name: ?[*:0]const u8) lib.Error!*c.plthook_t {
    var plthook_out: ?*internal.plthook_t = undefined;
    return switch (@as(lib.Result, @enumFromInt(internal.plthook_open_real(
        &plthook_out,
        image_idx,
        // need to cast from dyld._ to internal._
        @ptrCast(mh),
        image_name,
    )))) {
        // need to cast from internal._ to c._
        .Success => @ptrCast(plthook_out.?),
        inline else => |tag| @field(lib.Error, @tagName(tag)),
    };
}
