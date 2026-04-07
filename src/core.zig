const std = @import("std");
const win = std.os.windows;
const currentModName = @import("root").noita_asi_mod_name;

const lib = @import("root.zig");
const Scanner = lib.Scanner;
const NoitaString = lib.NoitaString;

/// Whenever the Shared struct is updated or otherwise backwards-incompatible
/// changes happen
const coreVersion = 1;

const Shared = extern struct {
    version: u32,
    loadedFrom: [*:0]const u8,
    startupTime: i128,
};

var shared: ?Shared = null;

const log = lib.log.mkLog("core");

export fn __noita_asi_mod_core() ?*Shared {
    return if (shared) |*ref| ref else null;
}

const GuiState = struct {
    ctx: *lib.gui.ImGuiContext,
    title: NoitaString,
    mods: std.ArrayList(NoitaString),
};

var guiState: ?GuiState = null;

fn buildModList() std.ArrayList(NoitaString) {
    var modList = std.ArrayList(NoitaString).initCapacity(lib.alloc, 4) catch @panic("OOM");

    const list = &win.peb().Ldr.InMemoryOrderModuleList;
    var current = list.Flink;

    while (current != list) : (current = current.Flink) {
        const entry: *win.LDR_DATA_TABLE_ENTRY = @fieldParentPtr("InMemoryOrderLinks", current);
        const module: win.HMODULE = @ptrCast(entry.DllBase);

        // const name = std.unicode.utf16LeToUtf8Alloc(lib.alloc, entry.BaseDllName.Buffer.?[0..entry.BaseDllName.Length]) catch |err| switch (err) {
        //     error.OutOfMemory => @panic("OOM"),
        //     else => @panic("bad unicode in DLL name"),
        // };
        // defer lib.alloc.free(name);

        if (win.kernel32.GetProcAddress(module, "noita_asi_mod_name")) |namePtr| {
            const nameFn: *const @TypeOf(currentModName) = @ptrCast(namePtr);
            modList.append(lib.alloc, NoitaString.fromSlice(std.mem.span(nameFn()))) catch @panic("OOM");
        }
    }

    return modList;
}

fn init() !void {
    const modName = currentModName();
    shared = .{
        .version = coreVersion,
        .loadedFrom = modName,
        .startupTime = std.time.nanoTimestamp(),
    };

    log(.debug, .default, "init (from {s})", .{modName});

    const scanner = Scanner.init();
    try lib.gui.scan(&scanner);

    const modManagerPush = try scanner.findStringPush("$menu_mods_settings", .{});
    const stringAssignCall = try scanner.text.scan(&.{0xE8}, .{ .at = modManagerPush + 5 });

    std.log.debug("Found string::assign CALL at {f}", .{lib.fmt.ptr(stringAssignCall)});

    try lib.patch.replaceCall(stringAssignCall, struct {
        pub var original: ?*const @TypeOf(replacement) = null;

        pub fn replacement(
            self: *lib.NoitaString,
            ptr: [*]u8,
        ) callconv(.{ .x86_thiscall = .{} }) *lib.NoitaString {
            const orig = original orelse unreachable;
            const res = orig(self, ptr);

            const state = if (guiState) |*ref| ref else b: {
                const newState = GuiState{
                    .ctx = lib.gui.ImGuiContext.init("noita-hook"),
                    .title = NoitaString.fromSlice("DLL patches installed:"),
                    .mods = buildModList(),
                };
                guiState = newState;
                break :b &newState;
            };

            state.ctx.startFrame(.{});

            var resp: lib.gui.UiResponse = undefined;
            var offset: f32 = 0;

            const x = 345;
            const y = 135;

            _ = state.ctx.text(
                &resp,
                1,
                &state.title,
                .{},
                0,
                1.0,
                &lib.gui.Font.default,
                &lib.gui.WidgetColor.white,
                x,
                y,
            );

            for (state.mods.items) |mod| {
                offset += 10;
                _ = state.ctx.text(
                    &resp,
                    1,
                    &mod,
                    .{ .draw_semi_transparent = true },
                    0,
                    1.0,
                    &lib.gui.Font.default,
                    &lib.gui.WidgetColor.white,
                    x + 5,
                    y + offset,
                );
            }

            return res;
        }
    });
}

var sharedRef: ?*Shared = null;

pub fn sharedData() *const Shared {
    if (sharedRef) |ref| {
        return ref;
    }
    if (shared) |*ref| {
        sharedRef = ref;
        return ref;
    }

    const list = &win.peb().Ldr.InMemoryOrderModuleList;
    var current = list.Flink;

    while (current != list) : (current = current.Flink) {
        const entry: *win.LDR_DATA_TABLE_ENTRY = @fieldParentPtr("InMemoryOrderLinks", current);
        const module: win.HMODULE = @ptrCast(entry.DllBase);
        if (win.kernel32.GetProcAddress(module, "__noita_asi_mod_core")) |func| {
            const coreFn: *const @TypeOf(__noita_asi_mod_core) = @ptrCast(func);
            if (coreFn()) |ref| {
                sharedRef = ref;
                return ref;
            }
        }
    }

    @panic("embedded core not found"); // should never happen
}

pub fn sharedInit() void {
    _ = win.kernel32.CreateEventExW(null, std.unicode.utf8ToUtf16LeStringLiteral("Local\\NoitaAsiModCoreInit"), 0, 0) orelse return;
    if (win.GetLastError() != .ALREADY_EXISTS) {
        init() catch |err| {
            log(.err, .default, "errored with {}", .{err});
            std.process.abort();
        };
        return;
    }
    const data = sharedData();
    const msg = "Incompatible ASI mods: {s} and {s}, the latter should update their version of noita-hook :(";
    if (data.version > coreVersion) {
        log(.err, .default, msg, .{ data.loadedFrom, currentModName() });
    } else if (data.version < coreVersion) {
        log(.err, .default, msg, .{ currentModName(), data.loadedFrom });
    } else {
        return;
    }
    @panic("incompatible ASI mods");
}
