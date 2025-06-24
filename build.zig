const std = @import("std");

pub fn build(b: *std.Build) void {
    const dll = b.addSharedLibrary(.{
        .name = "winmm",
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .x86,
            .os_tag = .windows,
            .abi = .gnu,
        }),
        .optimize = b.standardOptimizeOption(.{}),
    });

    dll.linkLibC();

    const debug_logs = b.option(bool, "debug-logs", "emit debug logs") orelse false;
    const options = b.addOptions();
    options.addOption(bool, "debug_logs", debug_logs);
    dll.root_module.addOptions("build_options", options);

    b.installArtifact(dll);
}
