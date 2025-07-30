const builtin = @import("builtin");
const std = @import("std");

const root = @import("root.zig");

const import_address_entry_t = extern struct {
    mod_name: [*:0]const u8,
    name: [*:0]const u8,
    addr: **anyopaque,
};

const Plthook = extern struct {
    mod: std.os.windows.HMODULE,
    num_entries: c_uint,
    entries: [1]import_address_entry_t,

    fn getEntries(self: *@This()) []import_address_entry_t {
        const entries: [*]import_address_entry_t = @ptrCast(&self.entries);
        return entries[0..self.num_entries];
    }
};

/// Returns `-1` when the end is reached.
export fn plthook_enum(plthook: *Plthook, pos: *c_uint, name_out: *?[*:0]const u8, addr_out: *?**anyopaque) c_int {
    const entries = plthook.getEntries();
    if (pos.* >= entries.len) {
        // TODO: remove
        name_out.* = null;
        addr_out.* = null;
        return -1;
    }
    name_out.* = entries[pos.*].name;
    addr_out.* = entries[pos.*].addr;
    pos.* += 1;
    return 0;
}

fn replace_funcaddr(addr: **anyopaque, newfunc: *anyopaque, oldfunc: ?**anyopaque) void {
    var dwOld: std.os.windows.DWORD = 0;

    if (oldfunc) |p| {
        p.* = addr.*;
    }
    std.os.windows.VirtualProtect(@ptrCast(addr), @sizeOf(*anyopaque), std.os.windows.PAGE_EXECUTE_READWRITE, &dwOld) catch |e| {
        std.debug.panic("VirtualProtect failed to remove protection: {}", .{e});
    };
    addr.* = newfunc;

    var dwDummy: std.os.windows.DWORD = 0;
    std.os.windows.VirtualProtect(@ptrCast(addr), @sizeOf(*anyopaque), dwOld, &dwDummy) catch |e| {
        std.debug.print("VirtualProtect failed to restore protection: {}", .{e});
    };
}

export fn plthook_replace(plthook: *Plthook, funcname_p: [*:0]const u8, funcaddr: *anyopaque, oldfunc: **anyopaque) root.Result {
    const funcname = std.mem.span(funcname_p);
    if (funcname.len == 0) return .InvalidArgument;

    const import_by_ordinal = funcname[0] != '?' and std.mem.indexOf(u8, funcname, ":@") != null;

    const addr = for (plthook.getEntries()) |entry| {
        const name = std.mem.span(entry.name);
        if (import_by_ordinal) {
            if (std.ascii.eqlIgnoreCase(name, funcname)) {
                break entry.addr;
            }
        } else {
            // import by name
            if (builtin.target.ptrBitWidth() == 64) {
                if (std.mem.eql(u8, name, funcname)) {
                    break entry.addr;
                }
            } else {
                // Function names may be decorated in Windows 32-bit applications.
                if (name.len >= funcname.len and std.mem.eql(u8, name[0..funcname.len], funcname)) {
                    if (name[funcname.len] == 0 or name[funcname.len] == '@') {
                        break entry.addr;
                    }
                }
                if (name[0] == '_' or name[0] == '@') {
                    const name1 = name[1..];
                    if (std.mem.eql(u8, name1[0..funcname.len], funcname)) {
                        if (name1[funcname.len] == 0 or name1[funcname.len] == '@') {
                            break entry.addr;
                        }
                    }
                }
            }
        }
    } else {
        clear_errmsg();
        append_errmsg_s("no such function: ");
        append_errmsg_s(funcname);
        return .FunctionNotFound;
    };
    replace_funcaddr(addr, funcaddr, oldfunc);
    return .Success;
}

var errbuf = std.mem.zeroes([1024:0]u8);

export fn plthook_error() [*:0]const u8 {
    return &errbuf;
}

export fn clear_errmsg() void {
    errbuf[0] = 0;
}

export fn append_errmsg_s(str: [*:0]const u8) void {
    const slice = std.mem.span(str);
    const n = std.mem.span(plthook_error()).len;
    const rem = errbuf[n..];
    const n_cpy = @min(rem.len, slice.len);
    @memcpy(rem[0 .. n_cpy + 1], slice[0 .. n_cpy + 1]);
}

export fn append_errmsg_i(i: usize) void {
    const n = std.mem.span(plthook_error()).len;
    _ = std.fmt.bufPrintZ(errbuf[n..], "{}", .{i}) catch {
        errbuf[n] = 0;
    };
}

export fn append_errmsg_ix(i: usize) void {
    const n = std.mem.span(plthook_error()).len;
    _ = std.fmt.bufPrintZ(errbuf[n..], "{x}", .{i}) catch {
        errbuf[n] = 0;
    };
}

inline fn MAKELANGID(p: c_ushort, s: c_ushort) std.os.windows.LANGID {
    return (s << 10) | p;
}

export fn append_errmsg_win() void {
    const n = std.mem.span(plthook_error()).len;
    var buf_wstr: [614:0]u16 = undefined;
    const len_w = std.os.windows.kernel32.FormatMessageW(
        std.os.windows.FORMAT_MESSAGE_FROM_SYSTEM | std.os.windows.FORMAT_MESSAGE_IGNORE_INSERTS,
        null,
        std.os.windows.GetLastError(),
        MAKELANGID(std.os.windows.LANG.NEUTRAL, std.os.windows.SUBLANG.DEFAULT),
        &buf_wstr,
        buf_wstr.len,
        null,
    );
    if (std.unicode.calcWtf8Len(buf_wstr[0..len_w]) <= errbuf[n..].len) {
        const len = std.unicode.utf16LeToUtf8(errbuf[n..], buf_wstr[0..len_w]) catch {
            errbuf[n] = 0;
            return;
        };
        errbuf[n + len] = 0;
    }
}

export fn winsock2_ordinal2name(ordinal: c_int) ?[*:0]const u8 {
    return switch (ordinal) {
        1 => "accept",
        2 => "bind",
        3 => "closesocket",
        4 => "connect",
        5 => "getpeername",
        6 => "getsockname",
        7 => "getsockopt",
        8 => "htonl",
        9 => "htons",
        10 => "inet_addr",
        11 => "inet_ntoa",
        12 => "ioctlsocket",
        13 => "listen",
        14 => "ntohl",
        15 => "ntohs",
        16 => "recv",
        17 => "recvfrom",
        18 => "select",
        19 => "send",
        20 => "sendto",
        21 => "setsockopt",
        22 => "shutdown",
        23 => "socket",
        24 => "MigrateWinsockConfiguration",
        51 => "gethostbyaddr",
        52 => "gethostbyname",
        53 => "getprotobyname",
        54 => "getprotobynumber",
        55 => "getservbyname",
        56 => "getservbyport",
        57 => "gethostname",
        101 => "WSAAsyncSelect",
        102 => "WSAAsyncGetHostByAddr",
        103 => "WSAAsyncGetHostByName",
        104 => "WSAAsyncGetProtoByNumber",
        105 => "WSAAsyncGetProtoByName",
        106 => "WSAAsyncGetServByPort",
        107 => "WSAAsyncGetServByName",
        108 => "WSACancelAsyncRequest",
        109 => "WSASetBlockingHook",
        110 => "WSAUnhookBlockingHook",
        111 => "WSAGetLastError",
        112 => "WSASetLastError",
        113 => "WSACancelBlockingCall",
        114 => "WSAIsBlocking",
        115 => "WSAStartup",
        116 => "WSACleanup",
        151 => "__WSAFDIsSet",
        500 => "WEP",
        1000 => "WSApSetPostRoutine",
        1001 => "WsControl",
        1002 => "closesockinfo",
        1003 => "Arecv",
        1004 => "Asend",
        1005 => "WSHEnumProtocols",
        1100 => "inet_network",
        1101 => "getnetbyname",
        1102 => "rcmd",
        1103 => "rexec",
        1104 => "rresvport",
        1105 => "sethostname",
        1106 => "dn_expand",
        1107 => "WSARecvEx",
        1108 => "s_perror",
        1109 => "GetAddressByNameA",
        1110 => "GetAddressByNameW",
        1111 => "EnumProtocolsA",
        1112 => "EnumProtocolsW",
        1113 => "GetTypeByNameA",
        1114 => "GetTypeByNameW",
        1115 => "GetNameByTypeA",
        1116 => "GetNameByTypeW",
        1117 => "SetServiceA",
        1118 => "SetServiceW",
        1119 => "GetServiceA",
        1120 => "GetServiceW",
        1130 => "NPLoadNameSpaces",
        1131 => "NSPStartup",
        1140 => "TransmitFile",
        1141 => "AcceptEx",
        1142 => "GetAcceptExSockaddrs",
        else => null,
    };
}
