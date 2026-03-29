const std = @import("std");
const win = std.os.windows;

const cpp = @import("cpp.zig");
const dll_proxy = @import("dll-proxy.zig");
const payload = @import("payload.zig");

pub const std_options = std.Options{ .logFn = log };

pub fn DllMain(hModule: ?win.HINSTANCE, dwReason: u32, lpReserved: ?*anyopaque) callconv(.winapi) win.BOOL {
    _ = hModule;
    _ = lpReserved;

    // std.os.windows doesn't have those :(
    const DLL_PROCESS_ATTACH = 1;
    const DLL_PROCESS_DETACH = 0;

    switch (dwReason) {
        DLL_PROCESS_ATTACH => {
            init_stdout();

            dll_proxy.init() catch |err| {
                popupError("Original winmm.dll not found. Bad WINEDLLOVERRIDES on Linux? ({})", .{err});
                return win.FALSE;
            };

            payload.run() catch |err| {
                popupError(
                    \\The injection failed. Error code: {s}.
                    \\You can remove the winmm.dll from the game folder if you want to just run the game, but unsafe workshop mods will not work
                , .{@errorName(err)});
                return win.FALSE;
            };
        },
        DLL_PROCESS_DETACH => dll_proxy.deinit(),
        else => {},
    }
    return win.TRUE;
}

extern "kernel32" fn AttachConsole(dwProcessId: win.DWORD) callconv(.winapi) win.BOOL;
extern "kernel32" fn SetStdHandle(nStdHandle: win.DWORD, hHandle: win.HANDLE) callconv(.winapi) win.BOOL;

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

// just add a prefix to our logs
fn log(comptime level: std.log.Level, comptime scope: @Type(.enum_literal), comptime format: []const u8, args: anytype) void {
    const level_txt = comptime level.asText();
    const scope_prefix = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";

    var buf: [1024]u8 = undefined;
    var stderr = std.debug.lockStderrWriter(&buf);
    defer std.debug.unlockStderrWriter();

    stderr.print("[noita-dll-injection] " ++ level_txt ++ scope_prefix ++ format ++ "\n", args) catch return;
    stderr.flush() catch return;
}

fn popupError(comptime msg: []const u8, args: anytype) void {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    if (args_type_info != .@"struct") {
        @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
    }

    const text = if (args_type_info.@"struct".fields.len > 0) b: {
        var buf: [msg.len + 64:0]u8 = undefined;
        break :b std.fmt.bufPrintZ(&buf, msg, args) catch c: {
            @memcpy(buf[buf.len - 4 .. buf.len], "...\x00");
            break :c &buf;
        };
    } else msg ++ "\x00";

    std.debug.print("{s}", .{text});

    _ = MessageBoxA(null, text, "Noita DLL Injection Error", 0); // 0 = MB_OK
}

extern "user32" fn MessageBoxA(
    hWnd: ?std.os.windows.HWND,
    lpText: [*:0]const u8,
    lpCaption: [*:0]const u8,
    uType: u32,
) callconv(.winapi) i32;
