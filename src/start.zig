const std = @import("std");
const win = std.os.windows;

const config = @import("config");
const lib = @import("noita-hook");
const plugin = @import("plugin");

pub export fn noita_asi_mod_name() [*:0]const u8 {
    return config.plugin_name ++ "\x00";
}

pub fn DllMain(hinstDLL: win.HINSTANCE, fdwReason: win.DWORD, lpReserved: win.LPVOID) callconv(.winapi) win.BOOL {
    _ = hinstDLL;
    _ = lpReserved;

    if (fdwReason != 1) {
        return win.TRUE;
    }
    init_stdout();

    lib.core.sharedInit();

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

pub const std_options = std.Options{ .logFn = lib.log.mkLog(config.plugin_name) };

// add a little trace about which plugin exactly panicked
fn panicFn(msg: []const u8, first_trace_addr: ?usize) noreturn {
    std.log.err("panic!", .{});
    std.debug.defaultPanic(msg, first_trace_addr);
}

pub const panic = std.debug.FullPanic(panicFn);

comptime {
    _ = lib;
}
