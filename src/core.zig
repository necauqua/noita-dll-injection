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
    // ctx: *lib.gui.ImGuiContext,
    title: NoitaString,
    mods: std.ArrayList(NoitaString),
};

var guiState: ?GuiState = null;

fn getOrInitGuiState() *GuiState {
    if (guiState) |*state| {
        return state;
    }
    guiState = .{
        // .ctx = lib.gui.ImGuiContext.init("noita-hook"),
        .title = NoitaString.from("DLL patches installed:") catch @panic("OOM"),
        .mods = buildModList() catch @panic("OOM"),
    };
    return &guiState.?;
}

fn buildModList() error{OutOfMemory}!std.ArrayList(NoitaString) {
    var modList = try std.ArrayList(NoitaString).initCapacity(lib.alloc, 4);

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
            try modList.append(lib.alloc, try NoitaString.from(std.mem.span(nameFn())));
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
            const orig = original.?;
            const res = orig(self, ptr);

            const state = getOrInitGuiState();

            // Cannot cache the ImGuiContext in gui state because on soft restarts Noita seemingly
            // clears out the auto sets, which ImGuiContext is one of, so we'd get a dangling pointer then
            const ctx = lib.gui.ImGuiContext.init("noita-hook");
            defer ctx.deinit();

            ctx.startFrame(.{});

            var resp: lib.gui.UiResponse = undefined;
            var id: u32 = 1;

            const x = 355;
            var y: f32 = 135;

            _ = ctx.text(
                &resp,
                .{ .id = id },
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
                id += 1;
                y += 10;
                _ = ctx.text(
                    &resp,
                    .{ .id = id },
                    &mod,
                    .{ .bits = .{ .draw_semi_transparent = true } },
                    0,
                    1.0,
                    &lib.gui.Font.default,
                    &lib.gui.WidgetColor.white,
                    x + 5,
                    y,
                );
            }

            // var frameData = lib.gui.FrameData{
            //     .anchor_x = 10.0,
            //     .anchor_y = 10.0,
            //     .anchor_width = 100.0,
            //     .anchor_height = 10.0,
            //     .needs_render = true,
            //     .once_per_frame = false,
            // };
            // var text = NoitaString.from("test dll mod description") catch @panic("OOM");
            // defer text.deinit();

            // state.ctx.tooltip(&frameData, &resp, &text, &NoitaString.empty);

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
