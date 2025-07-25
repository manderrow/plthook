const std = @import("std");

pub const VMInherit = enum(std.c.vm_inherit_t) {
    share = std.c.VM.INHERIT.SHARE,
    copy = std.c.VM.INHERIT.COPY,
    none = std.c.VM.INHERIT.NONE,
    donate_copy = std.c.VM.INHERIT.DONATE_COPY,
    _,

    pub const default: VMInherit = .copy;
};

pub const VMBehavior = enum(std.c.vm_behavior_t) {
    default = std.c.VM.BEHAVIOR.DEFAULT,
    random = std.c.VM.BEHAVIOR.RANDOM,
    sequential = std.c.VM.BEHAVIOR.SEQUENTIAL,
    rseqntl = std.c.VM.BEHAVIOR.RSEQNTL,
    will_need = std.c.VM.BEHAVIOR.WILLNEED,
    dont_need = std.c.VM.BEHAVIOR.DONTNEED,
    free = std.c.VM.BEHAVIOR.FREE,
    zero_wired_pages = std.c.VM.BEHAVIOR.ZERO_WIRED_PAGES,
    reusable = std.c.VM.BEHAVIOR.REUSABLE,
    reuse = std.c.VM.BEHAVIOR.REUSE,
    can_reuse = std.c.VM.BEHAVIOR.CAN_REUSE,
    page_out = std.c.VM.BEHAVIOR.PAGEOUT,
    _,
};

pub const vm_address_t = std.c.vm_offset_t;
pub const memory_object_name_t = std.c.mach_port_t;

pub const KERN_SUCCESS = 0;
pub const KERN_INVALID_ADDRESS = 1;
