const builtin = @import("builtin");
const std = @import("std");

pub const c = @cImport(@cInclude("plthook.h"));
pub const system = switch (builtin.os.tag) {
    .macos => @import("macos.zig"),
    .windows => @import("windows.zig"),
    else => @import("elf.zig"),
};

comptime {
    _ = system;
}

pub const Result = enum(c_int) {
    Success = c.PLTHOOK_SUCCESS,
    FileNotFound = c.PLTHOOK_FILE_NOT_FOUND,
    InvalidFileFormat = c.PLTHOOK_INVALID_FILE_FORMAT,
    FunctionNotFound = c.PLTHOOK_FUNCTION_NOT_FOUND,
    InvalidArgument = c.PLTHOOK_INVALID_ARGUMENT,
    OutOfMemory = c.PLTHOOK_OUT_OF_MEMORY,
    InternalError = c.PLTHOOK_INTERNAL_ERROR,
    NotImplemented = c.PLTHOOK_NOT_IMPLEMENTED,
};

pub const Error = blk: {
    const fields: []const std.builtin.Type.EnumField = std.meta.fields(Result);
    var errors: [fields.len - 1]std.builtin.Type.Error = .{undefined} ** (fields.len - 1);
    var i = 0;
    for (fields) |field| {
        if (field.value == @intFromEnum(Result.Success)) continue;
        errors[i] = .{ .name = field.name };
        i += 1;
    }
    break :blk @Type(.{ .error_set = &errors });
};

fn adaptResult(result: Result) Error!void {
    return switch (result) {
        .Success => {},
        inline else => |tag| @field(Error, @tagName(tag)),
    };
}

pub fn openByName(name: ?[*:0]const u8) Error!*c.plthook_t {
    var plthook_out: ?*c.plthook_t = undefined;
    try adaptResult(@enumFromInt(c.plthook_open(&plthook_out, name)));
    return plthook_out.?;
}

pub fn openByAddress(address: usize) Error!*c.plthook_t {
    var plthook_out: ?*c.plthook_t = undefined;
    try adaptResult(@enumFromInt(c.plthook_open_by_address(&plthook_out, @ptrFromInt(address))));
    return plthook_out.?;
}

pub fn openByHandle(handle: *anyopaque) Error!*c.plthook_t {
    var plthook_out: ?*c.plthook_t = undefined;
    try adaptResult(@enumFromInt(c.plthook_open_by_handle(&plthook_out, handle)));
    return plthook_out.?;
}

pub fn openByFilename(name: [*:0]const u8) (error{FileNotFound} || Error)!*c.plthook {
    switch (builtin.os.tag) {
        .windows => @compileError("Unsupported OS"),
        .macos => {
            const info = system.getImageByFilename(name) orelse return error.FileNotFound;
            return system.open(info.idx, null, null);
        },
        else => {
            var ctx = system.HandleByNameContext{ .find_name = std.mem.span(name) };
            std.posix.dl_iterate_phdr(&ctx, error{Done}, system.HandleByNameContext.process) catch |e| {
                switch (e) {
                    error.Done => return openByAddress(ctx.result),
                }
            };
            return error.FileNotFound;
        },
    }
}

pub fn replace(plthook: *c.plthook_t, name: [:0]const u8, new_func: anytype) Error!@TypeOf(new_func) {
    const info = @typeInfo(@TypeOf(new_func));
    if (info != .pointer or info.pointer.size != .one or @typeInfo(info.pointer.child) != .@"fn") {
        @compileError("Expected a fn pointer, found " ++ @typeName(@TypeOf(new_func)));
    }
    var old_func: @TypeOf(new_func) = undefined;
    try adaptResult(@enumFromInt(c.plthook_replace(plthook, name, @constCast(@ptrCast(new_func)), @ptrCast(&old_func))));
    return old_func;
}
