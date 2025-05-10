const std = @import("std");

const utils = @import("utils.zig");
const parser = @import("parser.zig");

pub const ModuleContext = struct {
    fn treapCmp(lhs: []const u8, rhs: []const u8) std.math.Order {
        return std.mem.order(u8, lhs, rhs);
    }

    const MacrosTreap = std.Treap([]const u8, treapCmp);

    allocator: std.mem.Allocator,
    // arena_allocator: std.heap.ArenaAllocator,
    macros_nodes: std.SegmentedList(MacrosTreap.Node, 16),
    macros: MacrosTreap,

    pub fn init(allocator: std.mem.Allocator) ModuleContext {
        return .{
            .allocator = allocator,
            // .arena_allocator = .init(allocator),
            .macros_nodes = .{},
            .macros = .{},
        };
    }

    pub fn deinit(self: *ModuleContext) void {
        self.macros_nodes.deinit(self.allocator);
        // self.macros_nodes.deinit(self.arena_allocator);
        // self.arena_allocator.deinit();
    }
};

pub fn evaluateReadMacros(value: *parser.LispieValue, module_ctx: *ModuleContext, allocator: std.mem.Allocator) !utils.RefCount(parser.LispieValue) {
    switch (value.*) {
        .list => |*list| {
            switch (list.contents.items[0].value.*) {
                .symbol => |*sym| {
                    if (sym.prefix == .none and std.mem.eql(u8, sym.contents.items, "defmacro")) {
                        std.debug.print("Macro {s} defined", .{sym.contents.items});

                        var treap_entry = module_ctx.macros.getEntryFor(sym.contents.items);
                        const treap_node = try module_ctx.macros_nodes.addOne(allocator);
                        treap_entry.set(treap_node);
                    } else {}
                },
                else => {
                    var children_results = std.ArrayList(utils.RefCount(parser.LispieValue)).init(allocator);
                    for (list.contents.items) |*child| {
                        const child_result = try evaluateReadMacros(child.value, module_ctx, allocator);
                        try children_results.append(child_result);
                    }

                    const result_ptr = try allocator.create(parser.LispieValue);
                    result_ptr.* = .{ .list = .{
                        .par_type = list.par_type,
                        .prefix = list.prefix,
                        .contents = children_results,
                    } };
                    const result_rc = try utils.RefCount(parser.LispieValue).init(result_ptr, allocator);
                    return result_rc;
                }
            }
        },
        else => {},
    }

    const result_ptr = try allocator.create(parser.LispieValue);
    result_ptr.* = value.*;
    const result_rc = try utils.RefCount(parser.LispieValue).init(result_ptr, allocator);
    return result_rc;
}
