const std = @import("std");
const win = @cImport({
    @cInclude("windows.h");
});

// again the windows.h one does not work :(
extern "kernel32" fn GetModuleHandleA(lpModuleName: ?[*:0]const u8) callconv(.winapi) ?*opaque {};

fn debug(allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) !void {
    const msg = try std.fmt.allocPrintZ(allocator, fmt, args);
    _ = win.MessageBoxA(null, msg, "Debug", win.MB_OK);
}

pub fn run() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const base = @intFromPtr(win.GetModuleHandleA(null));

    try debug(allocator, "Base location is 0x{X}", .{base});
}
