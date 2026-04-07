const std = @import("std");

const alloc = @import("root.zig").alloc;

pub const NoitaString = extern struct {
    repr: extern union {
        small: [16]u8,
        heap: [*:0]u8,
    },
    len: u32,
    cap: u32,

    pub const empty: NoitaString = NoitaString.init();

    pub fn init() NoitaString {
        return .{
            .repr = .{ .small = std.mem.zeroes([16]u8) },
            .len = 0,
            .cap = 0xf,
        };
    }

    pub fn fromSlice(str: []const u8) NoitaString {
        var s = NoitaString.init();
        s.assign(str);
        return s;
    }

    pub fn deinit(s: *NoitaString) void {
        if (s.cap > 0xf) {
            alloc.free(s.repr.heap[0..s.cap]);
        }
        s.* = NoitaString.init();
    }

    pub fn asSlice(s: *const NoitaString) []const u8 {
        return if (s.cap <= 0xf) s.repr.small[0..s.len] else s.repr.heap[0..s.len];
    }

    pub fn assign(s: *NoitaString, str: []const u8) void {
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

        const heap = alloc.dupeZ(u8, str) catch @panic("OOM");

        s.deinit();

        s.repr.heap = heap;
        s.len = str.len;
        s.cap = str.len;
    }

    pub fn append(s: *NoitaString, str: []const u8) void {
        if (str.len == 0) return;

        const old_len = s.len;
        const new_len = old_len + str.len;

        if (new_len <= 0xf) {
            @memcpy(s.repr.small[old_len..new_len], str);
            s.repr.small[new_len] = 0;
            s.len = @intCast(new_len);
            s.cap = 0xf;
            return;
        }

        if (s.cap > 0xf and new_len <= s.cap) {
            @memcpy(s.repr.heap[old_len..new_len], str);
            s.repr.heap[new_len] = 0;
            s.len = @intCast(new_len);
            return;
        }

        var new_cap: usize = if (s.cap > 0xf) s.cap else 0xf;
        while (new_cap < new_len) {
            new_cap *= 2;
        }

        const heap = alloc.allocSentinel(u8, new_cap, 0) catch @panic("OOM");

        @memcpy(heap[0..old_len], s.asSlice());
        @memcpy(heap[old_len..new_len], str);

        s.deinit();

        s.repr.heap = heap;
        s.len = @intCast(new_len);
        s.cap = @intCast(new_cap);
    }

    pub fn resetCapacity(s: *NoitaString) void {
        if (s.cap <= 0xf) return;

        if (s.len <= 0xf) {
            var small = std.mem.zeroes([16]u8);
            const slice = s.asSlice();
            @memcpy(small[0..slice.len], slice);
            small[slice.len] = 0;

            s.deinit();
            s.repr.small = small;
            s.len = @intCast(slice.len);
            s.cap = 0xf;
            return;
        }

        if (s.cap == s.len) return;

        const heap = alloc.dupeZ(u8, s.asSlice()) catch @panic("OOM");

        s.deinit();

        s.repr.heap = heap;
        s.len = @intCast(heap.len);
        s.cap = @intCast(heap.len);
    }

    pub fn clone(s: *const NoitaString) NoitaString {
        return fromSlice(s.asSlice());
    }

    pub fn format(
        s: *const NoitaString,
        writer: anytype,
    ) !void {
        try writer.writeAll(s.asSlice());
    }
};
