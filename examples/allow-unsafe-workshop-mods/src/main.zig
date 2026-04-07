const std = @import("std");

const nh = @import("noita-hook");

pub fn init() !void {
    const scanner = nh.Scanner.init();

    try vectorAddPatch(&scanner);
    try modConfigCheckPatch(&scanner);
    try fixUnsafePopupPatch(&scanner);
}

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

fn vectorAddPatch(scanner: *const nh.Scanner) !void {
    const push = try scanner.findStringPush("settings.lua", .{ .skip = 1 });

    // 0x50 is PUSH EAX, 0xE8 is CALL <displacement>
    const vectorAddCall = (try scanner.text.scan(&.{ 0x50, 0xE8 }, .{ .at = push, .skip = 1 })) + 1;

    std.log.debug("Found a second __thiscall call at {f}", .{nh.fmt.ptr(vectorAddCall)});

    try nh.patch.replaceCall(vectorAddCall, struct {
        pub var original: ?*const @TypeOf(replacement) = null;

        pub fn replacement(vec: *opaque {}, value: *ReadMod) callconv(.{ .x86_thiscall = .{} }) void {
            if (value.invalid) {
                std.log.info("invalid=true mod found, patching: {f} (workshop id: {})", .{ value.name, value.workshop_id });
                value.invalid = false;
                value.request_no_api_restriction = true;
            }
            const o = original orelse unreachable;
            o(vec, value);
        }
    });
}

fn modConfigCheckPatch(scanner: *const nh.Scanner) !void {
    var offset = @intFromPtr(&scanner.text.bytes[0]);

    // the infinite loop breaks either if we find the thing, or the scan will fail after going through any matches
    const found = while (true) {
        // don't like this, but this CMP BYTE PTR [EAX + 0x93], 0x0 seems unique,
        // the only place where we put pointer to big mod struct into EAX and check for is_translation
        const isTranslationCmp = try scanner.text.scan(&.{ 0x80, 0xb8, 0x93, 0x00, 0x00, 0x00, 0x00 }, .{ .at = offset });
        std.log.debug("Found is_translation CMP at {f}", .{nh.fmt.ptr(isTranslationCmp)});

        // chack that the prev instruction (skipping a jz) is what we look for
        const request_no_api_restriction_cmp = isTranslationCmp - 2 - 7;
        const ptr: [*]u8 = @ptrFromInt(request_no_api_restriction_cmp);
        if (std.mem.eql(u8, ptr[0..7], &.{ 0x80, 0xb8, 0x90, 0x00, 0x00, 0x00, 0x00 })) {
            break request_no_api_restriction_cmp;
        }

        // in case the is_translation CMP *somehow* is not unique, we overall look for the
        // CMP is_translation preceeded by a CMP request_no_api_restriction skipping a JZ lol
        //
        // but this loop will usually only run once, a little goto action here
        offset = isTranslationCmp + 7;
    };

    std.log.debug("Found request_no_api_restriction CMP at {f}", .{nh.fmt.ptr(found)});

    // replace `CMP thing, 0` with `TEST thing, 0` (keeping the displacement)
    // to make the comparison always succeed
    try nh.patch.write(found, &.{ 0xF6, 0x80 });
}

fn fixUnsafePopupPatch(scanner: *const nh.Scanner) !void {
    const push = try scanner.findStringPush("$menu_mods_extraprivilegesnotification", .{});
    const function = try scanner.findFunctionContaining(push);

    std.log.debug("Found unsafe dialog function at {f}", .{nh.fmt.ptr(function)});

    const usage = try scanner.text.scan(function, .{});

    std.log.debug("Found unsafe dialog function usage at {f}", .{nh.fmt.ptr(usage)});

    const jump = try scanner.text.scan(&.{ 0x0F, 0x85 }, .{ .at = usage, .dir = .back });

    try nh.patch.write(jump, &(.{0x90} ** 6));
}
