const std = @import("std");

const utils = @import("utils.zig");
const parser = @import("parser.zig");

pub const ModuleContext = struct {
    fn treapCmp(lhs: []const u8, rhs: []const u8) std.math.Order {
        return std.mem.order(u8, lhs, rhs);
    }

    const MacrosTrie = utils.Trie(MacroDef);
    const MacroDef = struct {
        args: utils.RefCount(parser.LispieValue),
        body: utils.RefCount(parser.LispieValue),

        pub fn deinit(self: *MacroDef) void {
            self.args.unref();
            self.body.unref();
        }
    };

    allocator: std.mem.Allocator,
    // arena_allocator: std.heap.ArenaAllocator,
    macros: MacrosTrie,

    pub fn init(allocator: std.mem.Allocator) !ModuleContext {
        return .{
            .allocator = allocator,
            // .arena_allocator = .init(allocator),
            .macros = try MacrosTrie.init(allocator),
        };
    }

    pub fn deinit(self: *ModuleContext) void {
        self.macros.deinit();
        // self.macros_nodes.deinit(self.arena_allocator);
        // self.arena_allocator.deinit();
    }
};

pub fn evaluateReadMacros(value: *parser.LispieValue, module_ctx: *ModuleContext, allocator: std.mem.Allocator) !utils.RefCount(parser.LispieValue) {
    switch (value.*) {
        .list => |*list| {
            match_defmacro: {
                if (list.contents.items.len < 4) {
                    break :match_defmacro;
                }
                switch (list.contents.items[0].value.*) {
                    .symbol => |*sym_defmacro| {
                        if (sym_defmacro.prefix != .none or !std.mem.eql(u8, sym_defmacro.contents.items, "defmacro")) {
                            break :match_defmacro;
                        }
                    },
                    else => {
                        break :match_defmacro;
                    }
                }

                const macro_name_sym = switch (list.contents.items[1].value.*) {
                    .symbol => |*sym_name| sym_name,
                    else => {
                        break :match_defmacro;
                    },
                };

                std.debug.print("Macro {s} defined", .{macro_name_sym.contents.items});

                (try module_ctx.macros.get(macro_name_sym.contents.items, true)).?.args = list.contents.items[2].clone();
                (try module_ctx.macros.get(macro_name_sym.contents.items, true)).?.body = list.contents.items[3].clone();
            }
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
        },
        else => {
            const result_ptr = try allocator.create(parser.LispieValue);
            result_ptr.* = try value.clone(allocator);
            const result_rc = try utils.RefCount(parser.LispieValue).init(result_ptr, allocator);
            return result_rc;
        },
    }
}
