const builtin = @import("builtin");
const std = @import("std");

pub const c = @cImport(@cInclude("plthook.h"));
pub const macos = if (builtin.os.tag == .macos) @import("macos.zig");

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

test {
    std.testing.refAllDecls(macos);
}
