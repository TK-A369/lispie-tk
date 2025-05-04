const std = @import("std");

const utils = @import("utils.zig");
const parser = @import("parser.zig");

pub const ModuleContext = struct {
    arena_allocator: std.heap.ArenaAllocator,
    macros: std.Treap([]const u8, std.mem.order),

    fn init(allocator: std.mem.Allocator) ModuleContext {
        return .{
            .arena_allocator = .init(allocator),
            .macros = .{},
        };
    }
};

pub fn evaluateReadMacros(value: *parser.LispieValue) !utils.RefCount(parser.LispieValue) {
    switch (value.*) {
        .list => |*list| {
            switch (list.contents.items[0].value.*) {
                .symbol => |*sym| {
                    if (std.mem.eql(sym.items, "defmacro")) {
                        std.debug.print("Macro {s} defined", .{sym.items});
                    } else {}
                },
                else => {}
            }
        },
        else => {},
    }
}
