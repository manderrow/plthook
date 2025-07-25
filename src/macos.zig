const std = @import("std");

const root = @import("root.zig");
const c = root.c;
const internal = @cImport(@cInclude("plthook_osx_internal.h"));
const mach = @import("macos/mach.zig");

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

fn comptimeI2S(comptime i: comptime_int) []const u8 {
    return std.fmt.comptimePrint("{}", .{i});
}

export fn dump_maps(image_name: [*:0]const u8) void {
    const task = std.c.mach_task_self();
    var info = std.mem.zeroes(std.c.vm_region_basic_info_64);
    var info_count = std.c.VM.REGION.BASIC_INFO_COUNT;
    var object: mach.memory_object_name_t = 0;
    var addr: mach.vm_address_t = 0;
    var size: std.c.vm_size_t = 0;

    std.debug.print("MEMORY MAP({s})\n", .{image_name});
    std.debug.print(" start address    end address      protection    max_protection inherit     shared reserved offset   behavior         user_wired_count\n", .{});
    while (true) {
        switch (std.c.mach_vm_region(task, &addr, &size, std.c.VM.REGION.BASIC_INFO_64, @ptrCast(&info), &info_count, &object)) {
            mach.KERN_INVALID_ADDRESS => break,
            mach.KERN_SUCCESS => {},
            else => |rc| {
                std.debug.print("Unexpected return code from mach_vm_region: {}\n", .{rc});
            },
        }

        std.debug.print(" {x:0>16}-{x:0>16} {c}{c}{c}({x:0>8}) {c}{c}{c}({x:0>8})  {} {c}      {c}        {x:0>8} {} {}\n", .{
            addr,
            addr + size,
            @as(u8, if ((info.protection & std.c.PROT.READ) != 0) 'r' else '-'),
            @as(u8, if ((info.protection & std.c.PROT.WRITE) != 0) 'w' else '-'),
            @as(u8, if ((info.protection & std.c.PROT.EXEC) != 0) 'x' else '-'),
            info.protection,
            @as(u8, if ((info.max_protection & std.c.PROT.READ) != 0) 'r' else '-'),
            @as(u8, if ((info.max_protection & std.c.PROT.WRITE) != 0) 'w' else '-'),
            @as(u8, if ((info.max_protection & std.c.PROT.EXEC) != 0) 'x' else '-'),
            info.max_protection,
            info.inheritance,
            @as(u8, if (info.shared != 0) 'Y' else 'N'),
            @as(u8, if (info.reserved != 0) 'Y' else 'N'),
            info.offset,
            info.behavior,
            info.user_wired_count,
        });

        addr += size;
    }
}
