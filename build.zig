const std = @import("std");

pub const NoitaPluginOptions = struct {
    name: []const u8,
    module: ?*std.Build.Module = null,
    optimize: Optimize = .default,
    add_zls_check_step: bool = true,

    const Optimize = union(enum) {
        default: void, // equal to b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSmall })
        none: void,
        custom: std.builtin.OptimizeMode,
    };
};

fn win32(b: *std.Build) std.Build.ResolvedTarget {
    return b.resolveTargetQuery(.{
        .cpu_arch = .x86,
        .os_tag = .windows,
        .abi = .gnu,
    });
}

pub fn addNoitaPlugin(b: *std.Build, opts: NoitaPluginOptions) *std.Build.Step.Compile {
    const target = win32(b);

    const optimize = switch (opts.optimize) {
        .default => b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSmall }),
        .none => null,
        .custom => opts.optimize.custom,
    };

    const noita_hook = b.dependency("noita_hook", .{
        .target = target,
        .optimize = optimize,
    });

    const plugin = opts.module orelse b.createModule(.{ .root_source_file = b.path("src/main.zig") });

    plugin.addImport("noita-hook", noita_hook.module("lib"));
    plugin.addLibraryPath(noita_hook.path("lib"));

    const lib = b.addLibrary(.{
        .name = opts.name,
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .root_source_file = noita_hook.path("src/start.zig"),
            .link_libc = false,
            .target = target,
            .optimize = optimize,
        }),
    });
    lib.root_module.addImport("plugin", plugin);

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "plugin_name", opts.name);
    lib.root_module.addOptions("config", build_options);
    lib.out_filename = b.fmt("{s}.asi", .{std.fs.path.stem(lib.out_filename)});

    if (opts.add_zls_check_step) {
        var opts_mut = opts;
        opts_mut.add_zls_check_step = false;
        opts_mut.optimize = .{ .custom = .Debug };
        const check = addNoitaPlugin(b, opts_mut);
        b.step("check", "Check if it compiles").dependOn(&check.step);
    }

    return lib;
}

pub fn installNoitaPlugin(b: *std.Build, opts: NoitaPluginOptions) void {
    b.getInstallStep().dependOn(&b.addInstallArtifact(addNoitaPlugin(b, opts), .{
        .dest_dir = .{ .override = .{ .custom = "" } },
        .implib_dir = .disabled,
    }).step);
}

pub fn build(b: *std.Build) void {
    // we ignore the target options lol, its always a win32 dll
    _ = b.standardTargetOptions(.{});

    _ = b.addModule("lib", .{
        .root_source_file = b.path("src/root.zig"),
        .target = win32(b),
        .optimize = b.standardOptimizeOption(.{}),
    });

    const lib = b.addLibrary(.{
        .name = "noita-hook",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = win32(b),
            .optimize = .Debug,
        }),
    });
    b.step("check", "Check if it compiles").dependOn(&lib.step);
}
