const std = @import("std");
const win = std.os.windows;

const fmt = @import("fmt.zig");
const lib = @import("root.zig");

const log = std.log.scoped(.scanner);

pub const ScanFail = error{ScanFail};

pub const Section = struct {
    bytes: []const u8,

    const ScanParams = struct {
        /// Number of matches to skip
        skip: usize = 0,
        /// If set, the scan will start at this address(!)
        at: ?usize = null,
        /// Direction of the scan
        dir: enum {
            forward,
            back,
        } = .forward,
        // todo, add limit with a default of 4kb or smth (like did in noita-ts)
    };

    pub fn scan(s: *const Section, needle: anytype, params: ScanParams) ScanFail!usize {
        const bytes = lib.byteArgument(needle);
        switch (params.dir) {
            .forward => {
                var index: usize = if (params.at) |at| at - @intFromPtr(s.bytes.ptr) else 0;
                for (0..params.skip + 1) |_| {
                    index += bytes.len + (std.mem.indexOf(u8, s.bytes[index..], bytes) orelse return error.ScanFail);
                }
                return @intFromPtr(&s.bytes[index - bytes.len]);
            },
            .back => {
                var index: usize = if (params.at) |at| at - @intFromPtr(s.bytes.ptr) else s.bytes.len;
                for (0..params.skip + 1) |_| {
                    index = std.mem.lastIndexOf(u8, s.bytes[0..index], bytes) orelse return error.ScanFail;
                }
                return @intFromPtr(&s.bytes[index]);
            },
        }
    }
};

data: Section,
rdata: Section,
text: Section,

const Scanner = @This();

pub fn init() Scanner {
    const base = @intFromPtr(std.os.windows.kernel32.GetModuleHandleW(null));

    const e_lfanew = @as(*const u32, @ptrFromInt(base + 0x3c)).*;

    const pe: [*]u8 = @ptrFromInt(base + e_lfanew);
    if (!std.mem.eql(u8, pe[0..4], "PE\x00\x00")) {
        @panic("PE magic number not found");
    }

    const coff: *const std.coff.CoffHeader = @ptrFromInt(base + e_lfanew + 4);

    const sections: [*]const std.coff.SectionHeader =
        @ptrFromInt(base + e_lfanew + 4 + @sizeOf(std.coff.CoffHeader) + coff.size_of_optional_header);

    var data: ?Section = null;
    var rdata: ?Section = null;
    var text: ?Section = null;

    for (sections[0..coff.number_of_sections]) |section| {
        const sectionPtr: [*]u8 = @ptrFromInt(base + section.virtual_address);
        const res = Section{ .bytes = sectionPtr[0..section.virtual_size] };

        if (std.mem.eql(u8, &section.name, ".data\x00\x00\x00")) {
            data = res;
        } else if (std.mem.eql(u8, &section.name, ".rdata\x00\x00")) {
            rdata = res;
        } else if (std.mem.eql(u8, &section.name, ".text\x00\x00\x00")) {
            text = res;
        }
    }

    return .{
        .data = data orelse @panic("No .data section found"),
        .rdata = rdata orelse @panic("No .rdata section found"),
        .text = text orelse @panic("No .text section found"),
    };
}

pub fn findString(s: *const Scanner, comptime string: []const u8) ScanFail!usize {
    const location = s.rdata.scan(string ++ "\x00", .{}) catch {
        log.warn("String {f} not found", .{fmt.str(string)});
        return error.ScanFail;
    };
    log.debug("Found string {f} at {f}", .{ fmt.str(string), fmt.ptr(location) });
    return location;
}

pub fn findStringPush(s: *const Scanner, comptime string: []const u8, params: Section.ScanParams) ScanFail!usize {
    const strLoc = try s.findString(string);
    const location = s.text.scan([_]u8{0x68} ++ lib.byteArgument(strLoc), params) catch {
        log.warn("PUSH {f} #{} not found", .{ fmt.str(string), params.skip });
        return error.ScanFail;
    };
    log.debug("Found PUSH {f} #{} at {f}", .{ fmt.str(string), params.skip, fmt.ptr(location) });
    return location;
}

pub fn findFunctionContaining(s: *const Scanner, location: usize) ScanFail!usize {
    const prelude = [_]u8{
        0x55, // PUSH EBP
        0x8B, 0xEC, // MOV EBP, ESP
    };
    return try s.text.scan(&prelude, .{ .at = location, .dir = .back });
}
