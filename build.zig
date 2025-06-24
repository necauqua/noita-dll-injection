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

    b.installArtifact(dll);
}
