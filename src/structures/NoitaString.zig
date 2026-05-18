const std = @import("std");

const alloc = @import("../root.zig").alloc;

// hm you probably cant mark the outer file struct as extern sadly
pub const NoitaString = extern struct {
    const inline_cap: usize = 0xf;

    repr: extern union {
        small: [inline_cap + 1]u8,
        heap: [*]u8,
    },
    len: usize, // usize = u32 always as we're making 32bit DLLs, and it simplifies stuff
    cap: usize,

    pub const empty = NoitaString{
        .repr = .{ .small = std.mem.zeroes([inline_cap + 1]u8) },
        .len = 0,
        .cap = inline_cap,
    };

    pub fn initWithCapacity(cap: usize) error{ OutOfMemory, Overflow }!NoitaString {
        if (cap <= inline_cap) {
            return empty;
        }

        const heap = try alloc.alloc(u8, try std.math.add(usize, cap, 1));
        heap[0] = 0;

        return .{
            .repr = .{ .heap = heap.ptr },
            .len = 0,
            .cap = cap,
        };
    }

    pub fn deinit(s: *NoitaString) void {
        if (!s.isInline()) {
            const cap = std.math.add(usize, s.cap, 1) catch @panic("capacity overflow");
            alloc.free(s.repr.heap[0..cap]);
        }
        s.* = empty;
    }

    pub fn from(str: []const u8) error{OutOfMemory}!NoitaString {
        var s = empty;
        try s.assign(str);
        return s;
    }

    pub fn fromInline(str: []const u8) ?NoitaString {
        if (str.len > inline_cap) {
            return null;
        }

        var small = std.mem.zeroes([inline_cap + 1]u8);
        @memcpy(small[0..str.len], str);

        return .{
            .repr = .{ .small = small },
            .len = str.len,
            .cap = inline_cap,
        };
    }

    pub fn fromInlineComptime(comptime str: []const u8) NoitaString {
        if (str.len > inline_cap) {
            @compileError("literal too long for inline string");
        }
        return NoitaString.fromInline(str).?;
    }

    fn isInline(s: *const NoitaString) bool {
        // std::string destructor looks like:
        //  if (0xf < str->cap) operator_delete(str->repr->ptr);
        return s.cap <= inline_cap;
    }

    pub fn span(s: *const NoitaString) []const u8 {
        if (s.isInline()) {
            std.debug.assert(s.len <= inline_cap);
            return s.repr.small[0..s.len];
        }
        std.debug.assert(s.len <= s.cap);
        return s.repr.heap[0..s.len];
    }

    pub fn assign(s: *NoitaString, str: []const u8) error{OutOfMemory}!void {
        if (str.len <= inline_cap) {
            s.deinit();
            s.* = NoitaString.fromInline(str).?;
            return;
        }

        if (!s.isInline() and s.cap >= str.len) {
            @memcpy(s.repr.heap[0..str.len], str);
            s.repr.heap[str.len] = 0;
            s.len = str.len;
            return;
        }

        const heap = try alloc.dupeZ(u8, str);
        s.deinit();

        s.repr.heap = heap.ptr;
        s.len = str.len;
        s.cap = str.len;
    }

    pub fn append(s: *NoitaString, str: []const u8) error{ OutOfMemory, Overflow }!void {
        if (str.len == 0) {
            return;
        }

        const old_len = s.len;
        const new_len = try std.math.add(usize, old_len, str.len);

        if (s.isInline() and new_len <= inline_cap) {
            @memcpy(s.repr.small[old_len..new_len], str);
            s.repr.small[new_len] = 0;
            s.len = new_len;
            return;
        }

        if (!s.isInline() and new_len <= s.cap) {
            @memcpy(s.repr.heap[old_len..new_len], str);
            s.repr.heap[new_len] = 0;
            s.len = new_len;
            return;
        }

        var new_cap = if (s.isInline()) inline_cap else s.cap;

        // prevent an infinite loop on invalid strings
        if (new_cap == 0) {
            @panic("invalid string state (capacity=0)");
        }

        if (new_cap < new_len) {
            // Find next power of 2 >= new_len
            new_cap = std.math.powi(usize, 2, std.math.log2_int_ceil(usize, new_len)) catch |err| switch (err) {
                error.Underflow => unreachable,
                error.Overflow => return error.Overflow,
            };
        }

        const heap = try alloc.alloc(u8, try std.math.add(usize, new_cap, 1));
        @memcpy(heap[0..old_len], s.span());
        @memcpy(heap[old_len..new_len], str);
        heap[new_len] = 0;

        s.deinit();

        s.repr.heap = heap.ptr;
        s.len = new_len;
        s.cap = new_cap;
    }

    pub fn resetCapacity(s: *NoitaString) error{OutOfMemory}!void {
        if (s.isInline() or s.cap == s.len) {
            return;
        }

        if (s.len <= inline_cap) {
            var small = std.mem.zeroes([inline_cap + 1]u8);
            const len = s.len;
            @memcpy(small[0..len], s.span());

            s.deinit();

            s.repr.small = small;
            s.len = len;
            s.cap = inline_cap;
            return;
        }

        const heap = try alloc.dupeZ(u8, s.span());

        s.deinit();

        s.repr.heap = heap.ptr;
        s.len = heap.len;
        s.cap = heap.len;
    }

    pub fn clone(s: *const NoitaString) error{OutOfMemory}!NoitaString {
        return from(s.span());
    }

    pub fn format(s: *const NoitaString, writer: anytype) !void {
        try writer.writeAll(s.span());
    }
};
