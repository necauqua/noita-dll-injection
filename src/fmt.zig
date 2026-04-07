const std = @import("std");

fn formatPtr(
    self: usize,
    writer: *std.Io.Writer,
) std.Io.Writer.Error!void {
    try writer.print("\x1b[2;35m0x{x:0>8}\x1b[0m", .{self});
}

pub fn ptr(ptr_: usize) std.fmt.Alt(usize, formatPtr) {
    return .{ .data = ptr_ };
}

fn formatStr(
    self: []const u8,
    writer: *std.Io.Writer,
) std.Io.Writer.Error!void {
    try writer.print("\x1b[2;32m\"{s}\"\x1b[0m", .{self});
}

pub fn str(str_: []const u8) std.fmt.Alt([]const u8, formatStr) {
    return .{ .data = str_ };
}
