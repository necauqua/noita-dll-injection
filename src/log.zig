const std = @import("std");

pub fn mkLog(name: []const u8) fn (
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const static = struct {
        fn log(
            comptime level: std.log.Level,
            comptime scope: @Type(.enum_literal),
            comptime format: []const u8,
            args: anytype,
        ) void {
            const scope_prefix = if (scope == .default) "" else "\x1b[2m" ++ @tagName(scope) ++ "\x1b[0m: ";
            const color = switch (level) {
                .err => "\x1b[31m",
                .warn => "\x1b[33m",
                .info => "\x1b[32m",
                .debug => "\x1b[36m",
            };
            const level_pad = switch (level) { // meh
                .err => "  ",
                .warn => "",
                .info => "   ",
                .debug => "  ",
            };

            const time = @import("core.zig").sharedData().startupTime;

            const elapsed_ns: u64 = @intCast(std.time.nanoTimestamp() -| time);
            const secs = elapsed_ns / std.time.ns_per_s;
            const frac = elapsed_ns % std.time.ns_per_s;

            const stderr = std.debug.lockStderrWriter(&[_]u8{});
            defer std.debug.unlockStderrWriter();

            stderr.print(
                "\x1b[2m{d}.{d:0>6}\x1b[0m " ++
                    color ++ level_pad ++ level.asText() ++ "\x1b[0m " ++
                    "\x1b[1m" ++ name ++ "\x1b[0m: " ++
                    scope_prefix ++
                    format ++ "\n",
                .{ secs, frac / std.time.ns_per_us } ++ args,
            ) catch return;
        }
    };

    return static.log;
}
