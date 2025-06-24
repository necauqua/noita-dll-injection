const std = @import("std");
const debug = @import("debug.zig");

const IMAGE_DOS_HEADER = extern struct {
    _skip: [60]u8,
    e_lfanew: u32,
};

const IMAGE_NT_HEADERS32 = extern struct {
    _skip1: [6]u8,
    NumberOfSections: u16,
    _skip2: [12]u8,
    SizeOfOptionalHeader: u16,
    _skip3: [2]u8,
};

const IMAGE_SECTION_HEADER = extern struct {
    Name: [8]u8,
    VirtualSize: u32,
    VirtualAddress: u32,
    _skip: [24]u8,
};

// again the windows.h one does not work :(
extern "kernel32" fn GetModuleHandleA(lpModuleName: ?[*:0]const u8) callconv(.winapi) ?*opaque {};

const ScanParams = struct {
    skip: usize = 0,
    after: ?usize = null,
};

pub const Section = struct {
    section: []const u8,

    pub fn scan(s: *const Section, needle: []const u8, params: ScanParams) ?usize {
        var index: usize = if (params.after) |after| after - @intFromPtr(&s.section[0]) else 0;

        var j = params.skip + 1;
        while (j > 0) {
            index += needle.len + (std.mem.indexOf(u8, s.section[index..], needle) orelse {
                return null;
            });
            j -= 1;
        }
        return @intFromPtr(&s.section[index - needle.len]);
    }
};

pub const Sections = struct {
    data: Section,
    rdata: Section,
    text: Section,

    pub fn find() !Sections {
        const base = @intFromPtr(GetModuleHandleA(null));
        const dos: *const IMAGE_DOS_HEADER = @ptrFromInt(base);
        const pe: *const IMAGE_NT_HEADERS32 = @ptrFromInt(base + dos.e_lfanew);

        const sections: [*]const IMAGE_SECTION_HEADER =
            @ptrFromInt(@intFromPtr(pe) + @sizeOf(IMAGE_NT_HEADERS32) + pe.SizeOfOptionalHeader);

        var data: ?Section = null;
        var rdata: ?Section = null;
        var text: ?Section = null;

        for (sections[0..pe.NumberOfSections]) |section| {
            const name = section.Name;
            if (std.mem.eql(u8, &name, ".data\x00\x00\x00")) {
                const ptr: [*]u8 = @ptrFromInt(base + section.VirtualAddress);
                data = Section{
                    .section = ptr[0..section.VirtualSize],
                };
            } else if (std.mem.eql(u8, &name, ".rdata\x00\x00")) {
                const ptr: [*]u8 = @ptrFromInt(base + section.VirtualAddress);
                rdata = Section{
                    .section = ptr[0..section.VirtualSize],
                };
            } else if (std.mem.eql(u8, &name, ".text\x00\x00\x00")) {
                const ptr: [*]u8 = @ptrFromInt(base + section.VirtualAddress);
                text = Section{
                    .section = ptr[0..section.VirtualSize],
                };
            }
        }

        return Sections{
            .data = data orelse return error.DataSectionNotFound,
            .rdata = rdata orelse return error.RdataSectionNotFound,
            .text = text orelse return error.TextSectionNotFound,
        };
    }
};
