const std = @import("std");

const nh = @import("noita-hook");

pub fn init() !void {
    const scanner = nh.Scanner.init();

    const push = try scanner.findStringPush("$menu_mods_moveup", .{});

    // third occurence of the PUSH EAX, CALL instructions after "$menu_mods_moveup"
    const drawButtonCall = (try scanner.text.scan(.{ 0x50, 0xE8 }, .{ .at = push, .skip = 2 })) + 1;

    std.log.debug("Found draw button call at {f}", .{nh.fmt.ptr(drawButtonCall)});

    try nh.patch.replaceCall(drawButtonCall, struct {
        pub var original: ?*const @TypeOf(replacement) = null;

        const ReadMod = extern struct {
            name: nh.NoitaString,
            _skip1: [120]u8,
            request_no_api_restriction: bool,
            _skip2: [151]u8,
            workshop_id: u64,
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

        const UiResponse = extern struct {
            clicked: bool,
            _unknown: bool,
            right_clicked: bool,
            hovered: bool,
            _ignored: [19]u32,
        };

        pub fn replacement(
            self: *opaque {},
            out_response: *UiResponse,
            id1: u32,
            id2: u32,
            text: *nh.NoitaString,
            flags1: u32,
            flags2: u32,
            layer: u32,
            scale: f32,
            font: *opaque {},
            color: *Color,
            x: f32,
            y: f32,
        ) callconv(.{ .x86_thiscall = .{} }) *UiResponse {
            // idk how brittle this is, probably very
            const mod = asm volatile ("movl %%esi, %[result]"
                : [result] "=r" (-> *ReadMod),
                :
                : .{ .memory = true });

            const orig = original orelse unreachable;

            const NON_INTERACTIVE = 0x4;
            const NEXT_SAME_LINE = 0x4000;

            var extra_flag: u32 = 0;

            // inject space for the banner into the drawn text
            if (mod.request_no_api_restriction) {
                const slice = text.asSlice();
                if (std.mem.startsWith(u8, slice, "[ ] ") or std.mem.startsWith(u8, slice, "[x] ")) {
                    var buf: [200]u8 = undefined;
                    text.assign(std.fmt.bufPrint(&buf, "{s}           {s}", .{ slice[0..3], slice[3..] }) catch &buf);
                }
                extra_flag = NEXT_SAME_LINE;
            }

            const resp = orig(self, out_response, id1, id2, text, flags1 | extra_flag, flags2, layer, scale, font, color, x, y);

            if (!mod.request_no_api_restriction) {
                return resp;
            }

            var prefix = nh.NoitaString.fromSlice("     [unsafe]");
            defer prefix.deinit();

            const flags: u32 = NON_INTERACTIVE;

            var c = Color{ .red = 1.0, .green = 0.2, .blue = 0.2 };

            if (resp.hovered) {
                c.green = 0.8;
                c.blue = 0.8;
            }

            var offset: f32 = 1.0;

            // todo: dont remember this flag - is it PRESSED?
            if (flags1 & 0x4000000 != 0) {
                c.alpha = 0.6;
                offset = 0.0;
            }

            var banner_resp: UiResponse = undefined;
            _ = orig(self, &banner_resp, id1 + 1, id2, &prefix, flags, 0, layer, scale, font, &c, x + offset, y);

            return resp;
        }
    });
}
