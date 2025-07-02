const std = @import("std");

fn mkLib(b: *std.Build, optimize: std.builtin.OptimizeMode) std.Build.LibraryOptions {
    return .{
        .name = "winmm",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .link_libc = true,
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .x86,
                .os_tag = .windows,
                .abi = .gnu,
            }),
            .optimize = optimize,
        }),
    };
}

pub fn build(b: *std.Build) void {
    b.installArtifact(b.addLibrary(mkLib(b, b.standardOptimizeOption(.{}))));

    // for zls
    const check = b.addLibrary(mkLib(b, .Debug));
    b.step("check", "Check if it compiles").dependOn(&check.step);
}
