const expect = @import("std").testing.expect;
const std = @import("std");

const Patcher = @import("patcher.zig");
const StdString = @import("cpp.zig").StdString;

const win = @cImport({
    @cInclude("windows.h");
});

const log = std.log.scoped(.payload);

pub fn run() !void {
    const patcher = try Patcher.init();

    try vectorAddPatch(&patcher);
    try modConfigCheckPatch(&patcher);
    try fixUnsafePopupPatch(&patcher);

    try addUnsafeModBanners(&patcher);
}

const ReadMod = extern struct {
    name: StdString,
    _skip1: [120]u8,
    request_no_api_restriction: bool,
    _skip2: [151]u8,
    workshop_id: u64,
    _compatibility: [2]u32,
    invalid: bool,
    _padding: [3]u8,
};

fn vectorAddPatch(patcher: *const Patcher) !void {
    const push = try patcher.findStringPush("settings.lua", .{ .skip = 1 });

    // 0x50 is PUSH EAX, 0xE8 is CALL <displacement>
    const vectorAddCall = (try patcher.text.scan(&[_]u8{ 0x50, 0xE8 }, .{ .at = push, .skip = 1 })) + 1;

    log.debug("Found a second __thiscall call at 0x{x}", .{vectorAddCall});

    try patcher.wrapCall(vectorAddCall, struct {
        pub var original: ?*const @TypeOf(replacement) = null;

        pub fn replacement(vec: *opaque {}, value: *ReadMod) callconv(.{ .x86_thiscall = .{} }) void {
            if (value.invalid) {
                log.debug("invalid=true mod found, patching: {s} (workshop id: {})", .{ value.name.as_slice(), value.workshop_id });
                value.invalid = false;
                value.request_no_api_restriction = true;
            }
            const o = original orelse unreachable;
            o(vec, value);
        }
    });
}

fn modConfigCheckPatch(patcher: *const Patcher) !void {
    var offset = @intFromPtr(&patcher.text.section[0]);

    // the infinite loop breaks either if we find the thing, or the scan will fail after going through any matches
    const found = while (true) {
        // don't like this, but this CMP BYTE PTR [EAX + 0x93], 0x0 seems unique,
        // the only place where we put pointer to big mod struct into EAX and check for is_translation
        const is_translation_cmp = try patcher.text.scan(&[_]u8{ 0x80, 0xb8, 0x93, 0x00, 0x00, 0x00, 0x00 }, .{ .at = offset });
        log.debug("Found is_translation CMP at 0x{x}", .{is_translation_cmp});

        // chack that the prev instruction (skipping a jz) is what we look for
        const request_no_api_restriction_cmp = is_translation_cmp - 2 - 7;
        const ptr: [*]u8 = @ptrFromInt(request_no_api_restriction_cmp);
        if (std.mem.eql(u8, ptr[0..7], &[_]u8{ 0x80, 0xb8, 0x90, 0x00, 0x00, 0x00, 0x00 })) {
            break request_no_api_restriction_cmp;
        }

        // in case the is_translation CMP *somehow* is not unique, we overall look for the
        // CMP is_translation preceeded by a CMP request_no_api_restriction skipping a JZ lol
        //
        // but this loop will usually only run once, a little goto action here
        offset = is_translation_cmp + 7;
    };

    log.debug("Found request_no_api_restriction CMP at 0x{x}", .{found});

    // replace `CMP thing, 0` with `TEST thing, 0` (keeping the displacement)
    // to make the comparison always succeed
    try patcher.write(found, &[_]u8{ 0xF6, 0x80 });
}

fn fixUnsafePopupPatch(patcher: *const Patcher) !void {
    const push = try patcher.findStringPush("$menu_mods_extraprivilegesnotification", .{});
    const function = try patcher.findFunctionContaining(push);

    log.debug("Found unsafe dialog function at 0x{x}", .{function});

    const usage = try patcher.text.scan(function, .{});

    log.debug("Found unsafe dialog function usage at 0x{x}", .{usage});

    const jump = try patcher.text.scan(&[_]u8{ 0x0F, 0x85 }, .{ .at = usage, .dir = .back });

    try patcher.write(jump, &[_]u8{0x90} ** 6);
}

fn addUnsafeModBanners(patcher: *const Patcher) !void {
    const push = try patcher.findStringPush("$menu_mods_moveup", .{});
    const drawButtonCall = (try patcher.text.scan(&[_]u8{ 0x50, 0xE8 }, .{ .at = push, .skip = 2 })) + 1;
    log.debug("Found draw button call at 0x{x}", .{drawButtonCall});

    try patcher.wrapCall(drawButtonCall, struct {
        pub var original: ?*const @TypeOf(replacement) = null;

        const Color = extern struct {
            flag: u32 = 4, // always 4?
            red: f32,
            green: f32,
            blue: f32,
            alpha: f32 = 1.0,
        };

        const Response = extern struct {
            clicked: bool,
            _unknown: bool,
            right_clicked: bool,
            hovered: bool,
            _ignored: [19]u32,
        };

        pub fn replacement(
            self: *opaque {},
            out_response: *Response,
            id1: u32,
            id2: u32,
            text: *StdString,
            flags1: u32,
            flags2: u32,
            layer: u32,
            scale: f32,
            font: *opaque {},
            color: *Color,
            x: f32,
            y: f32,
        ) callconv(.{ .x86_thiscall = .{} }) *Response {
            // idk how brittle this is, probably very
            const mod = asm volatile ("movl %%esi, %[result]"
                : [result] "=r" (-> *ReadMod),
                :
                : "memory"
            );
            const o = original orelse unreachable;

            const NEXT_SAME_LINE = 0x4000;
            const NON_INTERACTIVE = 0x4;

            var extra_flag: u32 = 0;
            if (mod.request_no_api_restriction) {
                const slice = text.as_slice();
                if (std.mem.startsWith(u8, slice, "[ ] ") or std.mem.startsWith(u8, slice, "[x] ")) {
                    var buf: [200]u8 = undefined;
                    text.assign(std.fmt.bufPrint(&buf, "{s}           {s}", .{ slice[0..3], slice[3..] }) catch "<error>");
                }
                extra_flag = NEXT_SAME_LINE;
            }

            const resp = o(self, out_response, id1, id2, text, flags1 | extra_flag, flags2, layer, scale, font, color, x, y);

            if (mod.request_no_api_restriction) {
                var prefix = StdString.fromSlice("     [unsafe]");
                defer prefix.deinit();

                const flags: u32 = NON_INTERACTIVE;

                var c = Color{
                    .red = 1.0,
                    .green = 0.2,
                    .blue = 0.2,
                };
                if (resp.hovered) {
                    c.green = 0.8;
                    c.blue = 0.8;
                }
                var offset: f32 = 1.0;
                if (flags1 & 0x4000000 != 0) {
                    c.alpha = 0.6;
                    offset = 0.0;
                }

                var response = std.mem.zeroes(Response);
                _ = o(self, &response, id1 + 1, id2, &prefix, flags, 0, layer, scale, font, &c, x + offset, y);
            }

            return resp;
        }
    });
}
