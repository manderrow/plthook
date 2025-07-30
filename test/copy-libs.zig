const std = @import("std");

pub fn main() !void {
    const gpa = std.heap.smp_allocator;
    var args = try std.process.argsWithAllocator(gpa);

    _ = args.next() orelse return error.MissingArgument;

    const in1 = args.next() orelse return error.MissingArgument;
    const in2 = args.next() orelse return error.MissingArgument;
    const out = args.next() orelse return error.MissingArgument;

    const out_dir = try std.fs.cwd().openDir(out, .{});
    try std.fs.cwd().copyFile(in1, out_dir, "plthook-dummy.dll", .{});
    try std.fs.cwd().copyFile(in2, out_dir, "plthook-test.dll", .{});
}
