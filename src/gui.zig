const std = @import("std");

const lib = @import("root.zig");
const NoitaString = lib.NoitaString;
const Scanner = lib.Scanner;

pub const WidgetColor = extern struct {
    flag: u32 = 4, // always 4, not sure what this is
    r: f32 = 0.0,
    g: f32 = 0.0,
    b: f32 = 0.0,
    a: f32 = 1.0,

    pub const white = WidgetColor{ .r = 1.0, .g = 1.0, .b = 1.0 };
};

pub const UiOptions = packed struct(u64) {
    _unused_0: u1 = 0,
    is_draggable: bool = false,
    non_interactive: bool = false,
    always_clickable: bool = false,
    click_cancels_double_click: bool = false,
    ignore_container: bool = false,
    no_position_tween: bool = false,
    force_focusable: bool = false,
    handle_double_click_as_click: bool = false,
    gamepad_default_widget: bool = false,
    layout_insert_outside_left: bool = false,
    layout_insert_outside_right: bool = false,
    layout_insert_outside_above: bool = false,
    layout_force_calculate: bool = false,
    layout_next_same_line: bool = false,
    layout_no_layouting: bool = false,
    align_horizontal_center: bool = false,
    align_left: bool = false,
    focus_snap_to_right_edge: bool = false,
    no_pixel_snap_y: bool = false,
    draw_always_visible: bool = false,
    draw_no_hover_animation: bool = false,
    draw_wobble: bool = false,
    draw_fade_in: bool = false,
    draw_scale_in: bool = false,
    draw_wave_animate_opacity: bool = false,
    draw_semi_transparent: bool = false,
    draw_active_widget_cursor_on_both_sides: bool = false,
    draw_active_widget_cursor_off: bool = false,
    text_rich_rendering: bool = false, // 29
    _unused_30_46: u17 = 0,
    no_sound: bool = false,
    hack_force_click: bool = false,
    hack_allow_duplicate_ids: bool = false,
    scroll_container_smooth: bool = false,
    is_extra_draggable: bool = false,
    _unused_52_61: u10 = 0,
    snap_to_center: bool = false,
    disabled: bool = false,
};

pub const UiResponse = extern struct {
    clicked: bool,
    double_clicked: bool,
    rightClicked: bool,
    hovered: bool,
    _unknown: [32]u8,
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    _unknown2: f32,
    drawX: f32,
    drawY: f32,
    drawWidth: f32,
    drawHeight: f32,
    _unknown3: [8]u8, // alignment mb?.
};

comptime {
    std.debug.assert(@sizeOf(UiResponse) == 0x50);
}

pub const ImGuiContext = extern struct {
    vftable: *extern struct {
        destroy: *const fn (self: *const ImGuiContext, dealloc: bool) callconv(.{ .x86_thiscall = .{} }) void,
    },

    _rest: [0x90 - 4]u8, // lmao
    // unknownBool: bool,
    // _pad: [3]u8,
    // state: extern struct {
    //     options: UiOptions,
    //     nextOptions: UiOptions,
    //     nextColor: WidgetColor,
    //     z: f32, // f32 or u32?
    //     nextZ: f32,
    //     nextZSet: bool,
    //     _align: [3]u8,
    //     last_response: UiResponse,
    // },
    // impl: *opaque {},
    // _maybeAlign: u32,

    var functions: GuiFunctions = undefined;

    pub fn deinit(self: *ImGuiContext) void {
        self.vftable.destroy(self, true);
    }

    pub fn init(name: []const u8) *ImGuiContext {
        const gui = lib.alloc.create(ImGuiContext) catch @panic("OOM");
        var noitaName = NoitaString.fromSlice(name);
        defer noitaName.deinit();
        return functions.init(gui, 90, &noitaName, true);
    }

    pub fn startFrame(
        self: *ImGuiContext,
        navigationFlags: packed struct(u32) {
            gamepad: bool = true,
            keyboard: bool = true,
            _unused: u30 = 0,
        },
    ) callconv(.{ .x86_thiscall = .{} }) void {
        functions.startFrame(self, navigationFlags);
    }

    pub fn text(
        self: *ImGuiContext,
        out: *UiResponse,
        id: u64,
        text_: *const NoitaString,
        flags: UiOptions,
        layer: u32,
        scale: f32,
        font: *const Font,
        color: *const WidgetColor,
        x: f32,
        y: f32,
    ) callconv(.{ .x86_thiscall = .{} }) *UiResponse {
        return functions.text(self, out, id, text_, flags, layer, scale, font, color, x, y);
    }
};

comptime {
    std.debug.assert(@sizeOf(ImGuiContext) == 0x90);
}

pub const Font = extern struct {
    font_file: NoitaString,
    is_pixel_font: bool,

    pub const default: Font = .{
        .font_file = NoitaString.empty,
        .is_pixel_font = true,
    };
};

pub const GuiFunctions = struct {
    init: *const fn (
        self: *ImGuiContext,
        unknown: u32, // given to the mouse event handler, could be layer/z level/priority?.
        name: *const NoitaString,
        unknown2: bool, // no idea, could be interactive?. its false for guis with no buttons/etc
    ) callconv(.{ .x86_thiscall = .{} }) *ImGuiContext,

    startFrame: *const @TypeOf(ImGuiContext.startFrame),
    text: *const @TypeOf(ImGuiContext.text),

    pub fn scan(self: *GuiFunctions, scanner: *const Scanner) !void {
        const guiInit = try callAfterStringPush(scanner, "LuaImGui", @FieldType(GuiFunctions, "init"));
        const guiText = try callAfterStringPush(scanner, "$menu_mods_enablinginvalid", @FieldType(GuiFunctions, "text"));

        const push = try scanner.findStringPush("Menu gui", .{});
        const push3 = try scanner.text.scan(&.{ 0x6a, 0x03 }, .{ .at = push });
        const call = try scanner.text.scan(&.{0xE8}, .{ .at = push3 });
        std.log.debug("Found CALL at {f}", .{lib.fmt.ptr(call)});

        self.* = .{
            .init = guiInit,
            .startFrame = callToFn(call, @FieldType(GuiFunctions, "startFrame")),
            .text = guiText,
        };
    }
};

fn callToFn(callLocation: usize, tpe: type) tpe {
    const callPtr: [*]u8 = @ptrFromInt(callLocation);
    const displacement = std.mem.readInt(i32, callPtr[1..5], .little);

    const base: isize = @intCast(callLocation + 5);
    const location: usize = @intCast(base + displacement);

    return @ptrFromInt(location);
}

fn callAfterStringPush(scanner: *const Scanner, comptime str: []const u8, tpe: type) !tpe {
    const push = try scanner.findStringPush(str, .{});
    const call = try scanner.text.scan(&.{0xE8}, .{ .at = push, .skip = 1 });
    std.log.debug("Found CALL at {f}", .{lib.fmt.ptr(call)});
    return callToFn(call, tpe);
}

pub fn scan(scanner: *const Scanner) !void {
    try ImGuiContext.functions.scan(scanner);
}
