const std = @import("std");

const cpp = @import("cpp.zig");
const dll_proxy = @import("dll-proxy.zig");
const payload = @import("payload.zig");

const win = @cImport({
    @cInclude("windows.h");
});

pub const std_options = std.Options{ .logFn = log };

pub fn DllMain(hModule: ?std.os.windows.HINSTANCE, dwReason: u32, lpReserved: ?*anyopaque) callconv(.winapi) win.BOOL {
    _ = hModule;
    _ = lpReserved;

    switch (dwReason) {
        win.DLL_PROCESS_ATTACH => {
            init_stdout();

            dll_proxy.init() catch {
                popupError("Original winmm.dll not found. Bad WINEDLLOVERRIDES on Linux?", .{});
                return win.FALSE;
            };
            cpp.init() catch {
                popupError("Failed to load msvcr120.dll, this should not happen", .{});
                return win.FALSE;
            };
            payload.run() catch |err| {
                popupError(
                    \\The injection failed. Error code: {s}.
                    \\You can remove the winmm.dll from the game folder if you want to just run the game, but unsafe workshop mods will not work
                , .{@errorName(err)});
                return win.FALSE;
            };

            return win.TRUE;
        },
        win.DLL_PROCESS_DETACH => {
            dll_proxy.deinit();
        },
        else => {},
    }
    return win.TRUE;
}

fn init_stdout() void {
    const stderr_handle = win.CreateFileA(
        "Z:\\dev\\fd\\2",
        win.GENERIC_WRITE,
        0,
        null,
        win.OPEN_EXISTING,
        win.FILE_ATTRIBUTE_NORMAL,
        null,
    ) orelse {
        // not wine?
        _ = win.AttachConsole(win.ATTACH_PARENT_PROCESS);
        return;
    };

    // for some reason /dev/fd/1 does not work :(
    _ = win.SetStdHandle(win.STD_OUTPUT_HANDLE, stderr_handle);
    _ = win.SetStdHandle(win.STD_ERROR_HANDLE, stderr_handle);
}

// just add a prefix to our logs
fn log(comptime level: std.log.Level, comptime scope: @Type(.enum_literal), comptime format: []const u8, args: anytype) void {
    const level_txt = comptime level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    const stderr = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stderr);
    const writer = bw.writer();

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    nosuspend {
        writer.print("[noita-dll-injection] " ++ level_txt ++ prefix2 ++ format ++ "\n", args) catch return;
        bw.flush() catch return;
    }
}

fn popupError(comptime msg: []const u8, args: anytype) void {
    const text = if (@typeInfo(@TypeOf(args)).@"struct".fields.len > 0) b: {
        var buf: [msg.len + 64]u8 = undefined;
        _ = std.fmt.bufPrintZ(&buf, msg, args) catch {
            @memcpy(buf[buf.len - 4 .. buf.len], "...\x00");
        };
        break :b &buf;
    } else msg ++ "\x00";

    _ = win.MessageBoxA(null, text, "Noita DLL Injection Error", win.MB_OK);
}
