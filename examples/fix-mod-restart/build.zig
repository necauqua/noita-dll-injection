const std = @import("std");

const nh = @import("noita_hook");

pub fn build(b: *std.Build) void {
    nh.installNoitaPlugin(b, .{ .name = "fix-mod-restart" });
}
