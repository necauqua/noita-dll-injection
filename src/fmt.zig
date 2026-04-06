const std = @import("std");

pub const Ptr = struct {
    ptr: usize,

    pub fn format(
        self: Ptr,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("\x1b[2;35m0x{x:0>8}\x1b[0m", .{self.ptr});
    }
};

pub const Str = struct {
    str: []const u8,

    pub fn format(
        self: Str,
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.print("\x1b[2;32m\"{s}\"\x1b[0m", .{self.str});
    }
};

pub fn ptr(ptr_: usize) Ptr {
    return .{ .ptr = ptr_ };
}

pub fn str(str_: []const u8) Str {
    return .{ .str = str_ };
}
