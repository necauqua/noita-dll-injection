const mem = @import("std").mem;

const operatorNew = @extern(
    *const fn (size: usize) callconv(.c) ?*anyopaque,
    .{ .name = "??2@YAPAXI@Z", .library_name = "msvcr120" },
);

const operatorDelete = @extern(
    *const fn (ptr: *anyopaque) callconv(.c) void,
    .{ .name = "??3@YAXPAX@Z", .library_name = "msvcr120" },
);

fn allocNew(state: *anyopaque, len: usize, alignment: mem.Alignment, ret_addr: usize) ?[*]u8 {
    _ = state;
    _ = ret_addr;
    _ = alignment;
    return @ptrCast(operatorNew(len)); // for now we just trust this returns align(8) or smth
}

fn allocFree(stater: *anyopaque, memory: []u8, alignment: mem.Alignment, ret_addr: usize) void {
    _ = stater;
    _ = alignment;
    _ = ret_addr;
    return operatorDelete(memory.ptr);
}

pub const alloc = mem.Allocator{
    .ptr = undefined,
    .vtable = &.{
        .alloc = allocNew,
        .free = allocFree,
        .remap = mem.Allocator.noRemap,
        .resize = mem.Allocator.noResize,
    },
};
