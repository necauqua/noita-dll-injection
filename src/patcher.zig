const std = @import("std");

const debug = @import("debug.zig");

const win = @cImport({
    @cInclude("windows.h");
});

// again the windows.h one does not work :(
extern "kernel32" fn GetModuleHandleA(lpModuleName: ?[*:0]const u8) callconv(.winapi) ?*opaque {};

pub const Section = struct {
    section: []const u8,

    const ScanParams = struct {
        /// Number of matches to skip
        skip: usize = 0,
        /// If set, the scan will start at this address(!)
        at: ?usize = null,
        /// Direction of the scan
        dir: union(enum) {
            forward,
            back,
        } = .forward,
    };

    pub fn scan(s: *const Section, needle: anytype, params: ScanParams) !usize {
        const bytes = toBytes(needle);
        switch (params.dir) {
            .forward => {
                var index: usize = if (params.at) |at| at - @intFromPtr(&s.section[0]) else 0;
                for (0..params.skip + 1) |_| {
                    index += bytes.len + (std.mem.indexOf(u8, s.section[index..], bytes) orelse return error.ScanFail);
                }
                return @intFromPtr(&s.section[index - bytes.len]);
            },
            .back => {
                var index: usize = if (params.at) |at| at - @intFromPtr(&s.section[0]) else s.section.len;
                for (0..params.skip + 1) |_| {
                    index = std.mem.lastIndexOf(u8, s.section[0..index], bytes) orelse return error.ScanFail;
                }
                return @intFromPtr(&s.section[index]);
            },
        }
    }
};

data: Section,
rdata: Section,
text: Section,

const Patcher = @This();

pub fn init() !Patcher {
    const base = @intFromPtr(GetModuleHandleA(null));

    const e_lfanew = @as(*const u32, @ptrFromInt(base + 0x3c)).*;

    const pe: [*]u8 = @ptrFromInt(base + e_lfanew);
    if (!std.mem.eql(u8, pe[0..4], "PE\x00\x00")) {
        @panic("Not PE?.");
    }

    const coff: *const std.coff.CoffHeader = @ptrFromInt(base + e_lfanew + 4);

    const sections: [*]const std.coff.SectionHeader =
        @ptrFromInt(base + e_lfanew + 4 + @sizeOf(std.coff.CoffHeader) + coff.size_of_optional_header);

    var data: ?Section = null;
    var rdata: ?Section = null;
    var text: ?Section = null;

    for (sections[0..coff.number_of_sections]) |section| {
        const ptr: [*]u8 = @ptrFromInt(base + section.virtual_address);
        const res = Section{ .section = ptr[0..section.virtual_size] };

        if (std.mem.eql(u8, &section.name, ".data\x00\x00\x00")) {
            data = res;
        } else if (std.mem.eql(u8, &section.name, ".rdata\x00\x00")) {
            rdata = res;
        } else if (std.mem.eql(u8, &section.name, ".text\x00\x00\x00")) {
            text = res;
        }
    }

    return Patcher{
        .data = data orelse return error.DataSectionNotFound,
        .rdata = rdata orelse return error.RdataSectionNotFound,
        .text = text orelse return error.TextSectionNotFound,
    };
}

pub fn findString(s: *const Patcher, comptime string: []const u8) !usize {
    const location = s.rdata.scan(string ++ "\x00", .{}) catch {
        debug.log(@src(), "String \"{s}\" not found", .{string});
        return error.StaticStringNotFound;
    };
    debug.log(@src(), "Found string \"{s}\" at 0x{x}", .{ string, location });
    return location;
}

pub fn findStringPush(s: *const Patcher, comptime string: []const u8, params: Section.ScanParams) !usize {
    const str = try s.findString(string);
    const location = s.text.scan([_]u8{0x68} ++ toBytes(str), params) catch {
        debug.log(@src(), "PUSH \"{s}\" #{} not found", .{ string, params.skip });
        return error.PushStringNotFound;
    };
    debug.log(@src(), "Found PUSH \"{s}\" #{} at 0x{x}", .{ string, params.skip, location });
    return location;
}

pub fn findFunctionContaining(s: *const Patcher, location: usize) !usize {
    const prelude = [_]u8{
        0x55, // PUSH EBP
        0x8B, 0xEC, // MOV EBP, ESP
    };
    return try s.text.scan(&prelude, .{ .at = location, .dir = .back });
}

pub fn write(s: *const Patcher, address: usize, patch: anytype) !void {
    _ = s;

    const bytes = toBytes(patch);

    var old_protect: win.DWORD = undefined;

    debug.log(@src(), "Un-protecting {} bytes at address 0x{x}", .{ bytes.len, address });

    const target: [*]u8 = @ptrFromInt(address);

    if (win.VirtualProtect(target, bytes.len, win.PAGE_EXECUTE_READWRITE, &old_protect) == 0) {
        return error.VirtualUnprotectFailed;
    }

    debug.log(@src(), "Patching {} bytes at address 0x{x} with {x}", .{ bytes.len, address, bytes });
    @memcpy(target[0..bytes.len], bytes);

    debug.log(@src(), "Re-protecting {} bytes at address 0x{x}", .{ bytes.len, address });

    _ = win.VirtualProtect(target, bytes.len, old_protect, &old_protect);
}

pub fn wrapCall(s: *const Patcher, callAddress: usize, comptime wrapper: type) !void {
    var ptr: [*]u8 = @ptrFromInt(callAddress);
    if (ptr[0] != 0xE8) {
        debug.log(@src(), "Trying to patch a CALL at 0x{x} which is not a CALL", .{callAddress});
        return error.NotACall;
    }

    const base = callAddress + 5;
    const location = base + std.mem.readInt(u32, ptr[1..5], .little);

    debug.log(@src(), "Patching CALL at 0x{x}, original function was 0x{x}", .{ callAddress, location });

    wrapper.original = @ptrFromInt(location);

    const ourFn = @intFromPtr(&wrapper.replacement);

    debug.log(@src(), "Patching CALL at 0x{x} to use our function at 0x{x}", .{ callAddress, ourFn });

    try s.write(callAddress + 1, ourFn - base);
}

inline fn toBytes(arg: anytype) switch (@TypeOf(arg)) {
    usize => *const [@sizeOf(usize)]u8,
    else => []const u8,
} {
    return switch (@TypeOf(arg)) {
        usize => std.mem.asBytes(&std.mem.nativeToLittle(usize, arg)),
        else => arg,
    };
}
