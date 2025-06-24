const std = @import("std");
const win = @cImport({
    @cInclude("windows.h");
});

pub fn popup(comptime fmt: []const u8, args: anytype) void {
    const alloc = std.heap.page_allocator;
    const msg = std.fmt.allocPrintZ(alloc, fmt, args) catch @panic("oom");
    defer alloc.free(msg);

    _ = win.MessageBoxA(null, msg, "Debug", win.MB_OK);
}

var file_handle: ?win.HANDLE = null;

pub fn log(comptime fmt: []const u8, args: anytype) void {
    if (comptime !@import("build_options").debug_logs) {
        return;
    }

    if (file_handle == null) {
        file_handle = win.CreateFileA("noita-dll-injection-log.txt", win.GENERIC_WRITE, 0, null, win.CREATE_ALWAYS, win.FILE_ATTRIBUTE_NORMAL, null);
        if (file_handle == win.INVALID_HANDLE_VALUE) {
            file_handle = null;
            return;
        }
    }

    if (file_handle) |handle| {
        const alloc = std.heap.page_allocator;
        const msg = std.fmt.allocPrint(alloc, fmt ++ "\n", args) catch @panic("oom");
        defer alloc.free(msg);

        var bytes_written: win.DWORD = 0;
        _ = win.WriteFile(handle, @ptrCast(msg), msg.len, &bytes_written, null);
        _ = win.FlushFileBuffers(handle);
    }
}
