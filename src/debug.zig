const std = @import("std");

const win = @cImport({
    @cInclude("windows.h");
});

var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
const alloc = arena.allocator();

pub fn popup(comptime fmt: []const u8, args: anytype) void {
    const msg = std.fmt.allocPrintZ(alloc, fmt, args) catch @panic("oom");
    defer alloc.free(msg);

    _ = win.MessageBoxA(null, msg, "Debug", win.MB_OK);
}

var file_handle: ?win.HANDLE = null;

pub fn log(src: std.builtin.SourceLocation, comptime fmt: []const u8, args: anytype) void {
    if (comptime !@import("build_options").debug_logs) {
        return;
    }

    const handle = file_handle orelse blk: {
        const h = win.CreateFileA("noita-dll-injection-log.txt", win.GENERIC_WRITE, 0, null, win.CREATE_ALWAYS, win.FILE_ATTRIBUTE_NORMAL | win.FILE_FLAG_NO_BUFFERING, null);
        if (h == win.INVALID_HANDLE_VALUE) {
            return;
        }
        break :blk h;
    };

    const suffix = ".zig";
    const file = if (std.mem.endsWith(u8, src.file, suffix))
        src.file[0 .. src.file.len - suffix.len]
    else
        src.file;

    const msg = std.fmt.allocPrint(alloc, "[{s}:{}] " ++ fmt ++ "\n", .{ file, src.line } ++ args) catch @panic("oom");
    defer alloc.free(msg);

    var bytes_written: win.DWORD = 0;
    _ = win.WriteFile(handle, @ptrCast(msg), msg.len, &bytes_written, null);
    _ = win.FlushFileBuffers(handle);
}
