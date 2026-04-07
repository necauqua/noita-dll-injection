const std = @import("std");

const cpp = @import("cpp.zig");
pub const NoitaString = cpp.NoitaString;
pub const fmt = @import("fmt.zig");
pub const patch = @import("patch.zig");
pub const Scanner = @import("Scanner.zig");

pub inline fn byteArgument(arg: anytype) switch (@TypeOf(arg)) {
    usize => *const [@sizeOf(usize)]u8,
    i32 => *const [@sizeOf(i32)]u8,
    else => []const u8,
} {
    const T = @TypeOf(arg);
    return switch (T) {
        usize => std.mem.asBytes(&std.mem.nativeToLittle(usize, arg)),
        i32 => std.mem.asBytes(&std.mem.nativeToLittle(i32, arg)),
        else => arg,
    };
}
