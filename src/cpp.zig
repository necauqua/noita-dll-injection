const std = @import("std");

const win = @cImport({
    @cInclude("windows.h");
});

var operator_new_ptr: ?*fn (size: usize) callconv(.C) ?*anyopaque = null;
var operator_delete_ptr: ?*fn (ptr: *anyopaque) callconv(.C) void = null;

const FARPROC = *opaque {};
extern "kernel32" fn GetProcAddress(hModule: win.HMODULE, lpProcName: win.LPCSTR) callconv(.{ .x86_stdcall = .{} }) ?FARPROC;

pub fn init() !void {
    const dll = win.LoadLibraryA("msvcr120.dll") orelse return error.MsvcrLinkFail;
    operator_new_ptr = @ptrCast(GetProcAddress(dll, "??2@YAPAXI@Z"));
    operator_delete_ptr = @ptrCast(GetProcAddress(dll, "??3@YAXPAX@Z"));
}

fn operator_new(size: usize) ?*anyopaque {
    if (operator_new_ptr) |f| {
        return f(size);
    } else {
        return null;
    }
}

fn operator_delete(ptr: *anyopaque) void {
    if (operator_delete_ptr) |f| {
        f(ptr);
    }
}

pub const StdString = extern struct {
    repr: extern union {
        small: [16]u8,
        heap: [*c]u8,
    },
    len: u32,
    cap: u32,

    pub fn init() StdString {
        return .{
            .repr = .{ .small = std.mem.zeroes([16]u8) },
            .len = 0,
            .cap = 0xf,
        };
    }

    pub fn fromSlice(str: []const u8) StdString {
        var s = StdString.init();
        s.assign(str);
        return s;
    }

    pub fn deinit(s: *StdString) void {
        if (s.cap > 0xf) {
            if (s.repr.heap) |ptr| {
                operator_delete(ptr);
            }
        }
        s.* = StdString.init();
    }

    pub fn as_slice(s: *const StdString) []const u8 {
        return if (s.cap <= 0xf) s.repr.small[0..s.len] else s.repr.heap[0..s.len];
    }

    pub fn assign(s: *StdString, str: []const u8) void {
        if (s.cap > 0xf) {
            if (s.repr.heap) |ptr| {
                operator_delete(ptr);
            }
        }
        if (str.len <= 0xf) {
            @memcpy(s.repr.small[0..str.len], str);
            s.repr.small[str.len] = 0;
            s.len = str.len;
            s.cap = 0xf;
        } else {
            const heap_size = str.len + 1;
            const heap: [*]u8 = @ptrCast(operator_new(heap_size) orelse @panic("oom"));

            @memcpy(heap[0..str.len], str);
            heap[str.len] = 0;

            s.repr.heap = heap;
            s.len = str.len;
            s.cap = str.len;
        }
    }

    pub fn clone(s: *const StdString) !StdString {
        return fromSlice(s.as_slice());
    }

    pub fn format(
        s: StdString,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("\"{s}\"", .{s.as_slice()});
    }
};
