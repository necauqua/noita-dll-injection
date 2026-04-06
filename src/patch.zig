const std = @import("std");
const win = std.os.windows;

const lib = @import("root.zig");
const ptr = lib.fmt.ptr;

const log = std.log.scoped(.patch);

pub fn write(address: usize, patch: anytype) win.VirtualProtectError!void {
    const bytes = lib.byteArgument(patch);
    const target: [*]u8 = @ptrFromInt(address);

    log.debug("Un-protecting {} bytes at address {f}", .{ bytes.len, ptr(address) });
    const oldProtect = try win.VirtualProtectEx(win.self_process_handle, target, bytes.len, win.PAGE_EXECUTE_READWRITE);

    log.debug("Patching {} bytes at address {f} with {x}", .{ bytes.len, ptr(address), bytes });
    @memcpy(target[0..bytes.len], bytes);

    log.debug("Re-protecting {} bytes at address {f}", .{ bytes.len, ptr(address) });
    _ = try win.VirtualProtectEx(win.self_process_handle, target, bytes.len, oldProtect);
}

pub fn replaceCall(callAddress: usize, comptime wrapper: type) !void {
    var fnPtr: [*]u8 = @ptrFromInt(callAddress);
    if (fnPtr[0] != 0xE8) {
        log.warn("Trying to patch a CALL at {f} which is not a CALL", .{ptr(callAddress)});
        return error.NotACall;
    }

    const base: isize = @intCast(callAddress + 5);
    const displacement = std.mem.readInt(i32, fnPtr[1..5], .little);
    const location: usize = @intCast(base + displacement);

    log.debug("Patching CALL at {f}, original function was {f}", .{ ptr(callAddress), ptr(location) });

    wrapper.original = @ptrFromInt(location);

    const ourFn = @intFromPtr(&wrapper.replacement);
    const ourDisplacement: i32 = @intCast(@as(isize, @intCast(ourFn)) - base);

    log.debug("Patching CALL at {f} to use our function at {f}", .{ ptr(callAddress), ptr(ourFn) });

    try write(callAddress + 1, ourDisplacement);
}
