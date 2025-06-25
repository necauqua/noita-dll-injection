const std = @import("std");

fn mkLib(b: *std.Build) std.Build.LibraryOptions {
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
        }),
    };
}

pub fn build(b: *std.Build) void {
    const lib = b.addLibrary(mkLib(b));
    lib.root_module.optimize = b.standardOptimizeOption(.{});

    const options = b.addOptions();
    options.addOption(bool, "debug_logs", b.option(bool, "debug-logs", "emit debug logs") orelse false);
    lib.root_module.addOptions("build_options", options);

    b.installArtifact(lib);

    // for zls
    const check = b.addLibrary(mkLib(b));
    const check_options = b.addOptions();
    check_options.addOption(bool, "debug_logs", true);
    check.root_module.addOptions("build_options", check_options);
    check.root_module.optimize = .Debug;

    b.step("check", "Check if it compiles").dependOn(&check.step);
}
