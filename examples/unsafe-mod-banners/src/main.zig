const std = @import("std");

const nh = @import("noita-hook");

pub fn init() !void {
    const scanner = nh.Scanner.init();

    const push = try scanner.findStringPush("$menu_mods_moveup", .{});

    // third occurence of the PUSH EAX, CALL instructions after "$menu_mods_moveup"
    const drawButtonCall = (try scanner.text.scan(&.{ 0x50, 0xE8 }, .{ .at = push, .skip = 2 })) + 1;

    std.log.debug("Found draw button call at {f}", .{nh.fmt.ptr(drawButtonCall)});

    try nh.patch.replaceCall(drawButtonCall, struct {
        pub var original: ?*const @TypeOf(replacement) = null;

        const ReadMod = extern struct {
            name: nh.NoitaString,
            _skip1: [120]u8,
            request_no_api_restriction: bool,
            _skip2: [151]u8,
            workshop_id: u64 align(4),
            _compatibility: [2]u32,
            invalid: bool,
            _padding: [3]u8,
        };

        const Color = extern struct {
            flag: u32 = 4, // always 4?
            red: f32,
            green: f32,
            blue: f32,
            alpha: f32 = 1.0,
        };

        pub fn replacement(
            self: *opaque {},
            out_response: *nh.gui.UiResponse,
            id: nh.gui.UiId,
            text: *nh.NoitaString,
            flags: nh.gui.UiOptions,
            layer: u32,
            scale: f32,
            font: *opaque {},
            color: *Color,
            x: f32,
            y: f32,
        ) callconv(.{ .x86_thiscall = .{} }) *nh.gui.UiResponse {
            // idk how brittle this is, probably very
            const mod: *ReadMod = asm volatile ("movl %%esi, %[result]"
                : [result] "=r" (-> *ReadMod),
                :
                : .{ .memory = true });

            var extra_flags: nh.gui.UiOptions = flags;

            const banner = "     [unsafe]";

            // inject space for the banner into the drawn text
            if (mod.request_no_api_restriction) {
                const slice = text.span();
                if (std.mem.startsWith(u8, slice, "[ ] ") or std.mem.startsWith(u8, slice, "[x] ")) {
                    const space = " " ** (banner.len - 2);
                    var updated = nh.NoitaString.initWithCapacity(slice.len + space.len) catch @panic("OOM");

                    updated.append(slice[0..3]) catch @panic("OOM");
                    updated.append(space) catch @panic("OOM");
                    updated.append(slice[3..]) catch @panic("OOM");

                    text.deinit();
                    text.* = updated;
                }
                extra_flags.bits.layout_next_same_line = true;
            }

            const orig = original.?;

            const resp = orig(self, out_response, id, text, extra_flags, layer, scale, font, color, x, y);

            // Respond with an increased x so next column gets offset
            // to account for the banner and (kinda) avoid overlaps.
            // Sadly, no way to *only* do this if any unsafe mods are present
            resp.x += 20.0;

            if (!mod.request_no_api_restriction) {
                return resp;
            }

            var c = Color{ .red = 1.0, .green = 0.2, .blue = 0.2 };

            if (resp.hovered) {
                c.green = 0.8;
                c.blue = 0.8;
            }

            var offset: f32 = 1.0;

            if (flags.bits.draw_semi_transparent) {
                c.alpha = 0.6;
                offset = 0.0;
            }

            var banner_resp: nh.gui.UiResponse = undefined;

            var prefix = nh.NoitaString.fromInlineComptime(banner);
            _ = orig(
                self,
                &banner_resp,
                .{ .id = id.id + (1 << 32) },
                &prefix,
                .{ .bits = .{ .non_interactive = true } },
                layer,
                scale,
                font,
                &c,
                x + offset,
                y,
            );

            return resp;
        }
    });
}
