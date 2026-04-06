const std = @import("std");
const win = std.os.windows;

const config = @import("config");
const plugin = @import("plugin");

var startup_time: i128 = 0;

pub fn DllMain(hinstDLL: win.HINSTANCE, fdwReason: win.DWORD, lpReserved: win.LPVOID) callconv(.winapi) win.BOOL {
    _ = hinstDLL;
    _ = lpReserved;

    if (fdwReason != 1) {
        return win.TRUE;
    }
    init_stdout();

    startup_time = std.time.nanoTimestamp();

    // const initInfo = @typeInfo(@TypeOf(plugin.init));
    // if (initInfo.@"fn".params.len != 0) {
    //     @compileError("The plugin's init function must not take any parameters");
    // }

    std.log.info("init", .{});
    plugin.init() catch |err| {
        std.log.err("errored with {}", .{err});
    };

    return win.TRUE;
}

extern "kernel32" fn AttachConsole(dwProcessId: win.DWORD) callconv(.winapi) win.BOOL;
extern "kernel32" fn SetStdHandle(nStdHandle: win.DWORD, hHandle: win.HANDLE) callconv(.winapi) win.BOOL;

// todo need to make this idempotent across dlls somehow, right now we're leaking file handles?.
fn init_stdout() void {
    const stderr_handle = win.kernel32.CreateFileW(
        std.unicode.utf8ToUtf16LeStringLiteral("Z:\\dev\\fd\\2"),
        win.GENERIC_WRITE,
        0,
        null,
        win.OPEN_EXISTING,
        win.FILE_ATTRIBUTE_NORMAL,
        null,
    );

    // not wine
    if (stderr_handle == win.INVALID_HANDLE_VALUE) {
        _ = AttachConsole(0xFFFFFFFF); // ATTACH_PARENT_PROCESS
        return;
    }

    // for some reason /dev/fd/1 does not work :(
    _ = SetStdHandle(win.STD_OUTPUT_HANDLE, stderr_handle);
    _ = SetStdHandle(win.STD_ERROR_HANDLE, stderr_handle);
}

fn log(comptime level: std.log.Level, comptime scope: @Type(.enum_literal), comptime format: []const u8, args: anytype) void {
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

    const elapsed_ns: u64 = @intCast(std.time.nanoTimestamp() -| startup_time);
    const secs = elapsed_ns / std.time.ns_per_s;
    const frac = elapsed_ns % std.time.ns_per_s;

    const stderr = std.debug.lockStderrWriter(&[_]u8{});
    defer std.debug.unlockStderrWriter();

    stderr.print(
        "\x1b[2m{d}.{d:0>6}\x1b[0m " ++
            color ++ level_pad ++ level.asText() ++ "\x1b[0m " ++
            "\x1b[1m" ++ config.plugin_name ++ "\x1b[0m: " ++
            scope_prefix ++
            format ++ "\n",
        .{ secs, frac / std.time.ns_per_us } ++ args,
    ) catch return;
}

pub const std_options = std.Options{ .logFn = log };

// add a little trace about which plugin exactly panicked
fn panicFn(msg: []const u8, first_trace_addr: ?usize) noreturn {
    std.log.err("panic!", .{});
    std.debug.defaultPanic(msg, first_trace_addr);
}

pub const panic = std.debug.FullPanic(panicFn);
