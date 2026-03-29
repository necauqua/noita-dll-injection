const std = @import("std");

const operator_new = @extern(
    *const fn (size: usize) callconv(.c) ?*anyopaque,
    .{ .name = "??2@YAPAXI@Z", .library_name = "msvcr120" },
);

const operator_delete = @extern(
    *const fn (ptr: *anyopaque) callconv(.c) void,
    .{ .name = "??3@YAXPAX@Z", .library_name = "msvcr120" },
);

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

    pub fn asSlice(s: *const StdString) []const u8 {
        return if (s.cap <= 0xf) s.repr.small[0..s.len] else s.repr.heap[0..s.len];
    }

    pub fn assign(s: *StdString, str: []const u8) void {
        if (str.len <= 0xf) {
            var small = std.mem.zeroes([16]u8);
            @memcpy(small[0..str.len], str);
            small[str.len] = 0;

            s.deinit();
            s.repr.small = small;
            s.len = str.len;
            s.cap = 0xf;
            return;
        }

        const heap_size = str.len + 1;
        const heap: [*]u8 = @ptrCast(operator_new(heap_size) orelse @panic("oom"));

        @memcpy(heap[0..str.len], str);
        heap[str.len] = 0;

        s.deinit();
        s.repr.heap = heap;
        s.len = str.len;
        s.cap = str.len;
    }

    pub fn clone(s: *const StdString) StdString {
        return fromSlice(s.asSlice());
    }

    pub fn format(
        s: *const StdString,
        writer: anytype,
    ) !void {
        try writer.writeAll(s.asSlice());
    }
};
