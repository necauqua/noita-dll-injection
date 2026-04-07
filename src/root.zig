const std = @import("std");

pub const alloc = @import("alloc.zig").alloc;
pub const core = @import("core.zig");
const cpp = @import("cpp.zig");
pub const NoitaString = cpp.NoitaString;
pub const fmt = @import("fmt.zig");
pub const gui = @import("gui.zig");
pub const log = @import("log.zig");
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

fn refAllDeclsRecursive(comptime T: type) void {
    inline for (comptime std.meta.declarations(T)) |decl| {
        if (@TypeOf(@field(T, decl.name)) == type) {
            switch (@typeInfo(@field(T, decl.name))) {
                .@"struct", .@"enum", .@"union", .@"opaque" => refAllDeclsRecursive(@field(T, decl.name)),
                else => {},
            }
        }
        _ = &@field(T, decl.name);
    }
}

comptime {
    refAllDeclsRecursive(@This());
}
