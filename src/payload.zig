const std = @import("std");
const win = @cImport({
    @cInclude("windows.h");
});
const scan = @import("scan.zig");
const debug = @import("debug.zig");

const StdString = extern struct {
    repr: extern union {
        small: [16]u8,
        heap: [*c]const u8,
    },
    len: u32,
    cap: u32,

    fn as_slice(s: *const StdString) []const u8 {
        return if (s.cap <= 0xf) s.repr.small[0..s.len :0] else s.repr.heap[0..s.len :0];
    }
};

const ReadMod = extern struct {
    name: StdString,
    _skip1: [0x78]u8,
    request_no_api_restriction: bool,
    _pad: [3]u8,
    _skip2: [164]u8,
    invalid: bool,
};

const StdVec = *opaque {};

var originalVectorAdd: ?*const fn (
    vec: *StdVec,
    value: *ReadMod,
) callconv(.{ .x86_thiscall = .{} }) void = null;

fn wrappedVectorAdd(
    vec: *StdVec,
    value: *ReadMod,
) callconv(.{ .x86_thiscall = .{} }) void {
    const original = originalVectorAdd orelse unreachable;

    if (value.invalid) {
        debug.log(" \"invalid\" mod found ({s})! Fixing it up", .{value.name.as_slice()});
        value.invalid = false;
        value.request_no_api_restriction = true;
    }

    original(vec, value);
}

pub fn run() !void {
    const sections = try scan.Sections.find();

    var location = sections.rdata.scan("settings.lua\x00", .{}) orelse {
        return error.SettingsLuaStringNotFound;
    };

    debug.log("Found \"settings.lua\\0\" at 0x{x}", .{location});

    const le_value = std.mem.nativeToLittle(usize, location);
    const push = [_]u8{0x68} ++ std.mem.asBytes(&le_value);

    location = sections.text.scan(push, .{ .skip = 1 }) orelse {
        return error.PushSettingsLuaNotFound;
    };

    debug.log("Found second PUSH \"settings.lua\\0\" 0x{x}", .{location});

    const vectorAddCall = sections.text.scan(&[_]u8{ 0x50, 0xE8 }, .{ .after = location, .skip = 1 }) orelse {
        return error.VectorAddCallNotFound;
    };

    debug.log("Found a second __thiscall call at 0x{x}", .{vectorAddCall + 1});

    const ptr: [*]u8 = @ptrFromInt(vectorAddCall + 2);

    const base = vectorAddCall + 2 + 4;
    const offset = std.mem.readInt(u32, ptr[0..4], .little);

    const original = base + offset;
    originalVectorAdd = @ptrFromInt(original);
    debug.log("Original call is to 0x{x}", .{original});

    const ourFn = @intFromPtr(&wrappedVectorAdd);

    debug.log("Replacing with call to 0x{x}", .{ourFn});

    var buffer: [4]u8 = undefined;
    std.mem.writeInt(u32, &buffer, ourFn - base, .little);

    try patchCode(vectorAddCall + 2, &buffer);
}

pub fn patchCode(address: usize, patch: []const u8) !void {
    var old_protect: win.DWORD = undefined;

    debug.log("Un-protecting {} bytes at address 0x{x}", .{ patch.len, address });

    const result = win.VirtualProtect(@ptrFromInt(address), patch.len, win.PAGE_EXECUTE_READWRITE, &old_protect);

    if (result == 0) {
        return error.VirtualUnprotectFailed;
    }

    const target: [*]u8 = @ptrFromInt(address);
    @memcpy(target[0..patch.len], patch);

    debug.log("Re-protecting {} bytes at address 0x{x}", .{ patch.len, address });
    _ = win.VirtualProtect(@ptrFromInt(address), patch.len, old_protect, &old_protect);

    // debug.log("Flushing instruction cache for {} bytes at address 0x{x}", .{ patch.len, address });
    // if (win.FlushInstructionCache(win.GetCurrentProcess(), @ptrFromInt(address), patch.len) == 0) {
    //     return error.FlushInstructionCacheFailed;
    // }
}
