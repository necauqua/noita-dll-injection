const std = @import("std");

const nh = @import("noita-hook");

fn hasArg(alloc: std.mem.Allocator, expected: []const u8) error{OutOfMemory}!bool {
    var args = try std.process.argsWithAllocator(alloc);
    defer args.deinit();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, expected)) {
            return true;
        }
    }
    return false;
}

pub fn init() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const workdirArg = "-always_store_userdata_in_workdir";

    if (!(try hasArg(alloc, workdirArg))) {
        std.log.info("no workdir arg, doing nothing", .{});
        return;
    }

    const scanner = nh.Scanner.init();

    std.log.info("found workdir arg, applying patch", .{});

    const initialArg = "-no_logo_splashes ";
    const initialArgLocation = try scanner.findStringPush(initialArg, .{});

    const newArg = initialArg ++ workdirArg ++ " ";

    // immediately before the push of the string there's a PUSH 18,
    // which is the length, which we patch as well
    try nh.patch.write(initialArgLocation - 1, &.{newArg.len});

    // and replace the push arg with our adjustment
    try nh.patch.write(initialArgLocation + 1, @intFromPtr(newArg));
}
