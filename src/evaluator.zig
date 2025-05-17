const std = @import("std");

const utils = @import("utils.zig");
const parser = @import("parser.zig");

pub const ModuleContext = struct {
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

pub const RuntimeContext = struct {
    const ValuesTrie = utils.Trie(utils.RefCount(parser.LispieValue));

    bindings: ValuesTrie,
    outer_ctx: ?utils.RefCount(RuntimeContext),

    pub fn init(allocator: std.mem.Allocator) !RuntimeContext {
        return .{
            .bindings = .init(allocator),
            .outer_ctx = null,
        };
    }

    pub fn deinit(self: *RuntimeContext) void {
        self.bindings.deinit();
        if (self.outer_ctx) |outer_ctx_nonull| {
            outer_ctx_nonull.unref();
        }
    }

    pub fn get_binding(self: *const RuntimeContext, name: []const u8) !?utils.RefCount(parser.LispieValue) {
        const result = try self.bindings.get(name, false);
        if (result) |result_nonull| {
            return result_nonull.clone();
        }
        if (self.outer_ctx) |outer_ctx_nonull| {
            return outer_ctx_nonull.value.get_binding(name);
        }
        return null;
    }
};

pub const RuntimeEvaluationError = error{
    EmptyCall,
    UncallableCallAttempt,
    MalformedFunctionArgs,
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

pub fn evaluateExpandMacros(
    value: *parser.LispieValue,
    module_ctx: *ModuleContext,
    allocator: std.mem.Allocator,
) !utils.RefCount(parser.LispieValue) {
    _ = module_ctx;

    switch (value.*) {
        // .list => |*list| {
        //     //TODO
        // },
        else => {
            const result_ptr = try allocator.create(parser.LispieValue);
            result_ptr.* = try value.clone(allocator);
            const result_rc = try utils.RefCount(parser.LispieValue).init(result_ptr, allocator);
            return result_rc;
        }
    }
}

pub fn evaluateRuntime(
    value: *parser.LispieValue,
    module_ctx: *ModuleContext,
    runtime_ctx: utils.RefCount(RuntimeContext),
    allocator: std.mem.Allocator,
) !utils.RefCount(parser.LispieValue) {
    switch (value.*) {
        .list => |*list| {
            if (list.items.len < 1) {
                return RuntimeEvaluationError.EmptyCall;
            }
            var function_evaluated = try evaluateRuntime(list.contents.items[0].value, module_ctx, allocator);
            defer function_evaluated.unref();

            var args_evaluated = std.ArrayList(utils.RefCount(parser.LispieValue)).init(allocator);
            for (1..list.items.len) |i| {
                try args_evaluated.append(try evaluateRuntime(
                    list.contents.items[i].value,
                    module_ctx,
                    allocator,
                ));
            }
            defer {
                for (args_evaluated.items) |ae| {
                    ae.unref();
                }
            }

            return try executeFunction(function_evaluated, args_evaluated, module_ctx, runtime_ctx, allocator);
        },
        .symbol => |*sym| {
            const binding_value = try runtime_ctx.value.get_binding(sym.contents.items);
            if (binding_value) |binding_value_nonull| {
                return binding_value_nonull;
            }

            const result_ptr = try allocator.create(parser.LispieValue);
            result_ptr.* = .{ .list = .{
                .par_type = .normal,
                .prefix = .none,
                .contents = .init(allocator),
            } };
            const result_rc = try utils.RefCount(parser.LispieValue).init(result_ptr, allocator);
            return result_rc;
        },
        else => {
            const result_ptr = try allocator.create(parser.LispieValue);
            result_ptr.* = try value.clone(allocator);
            const result_rc = try utils.RefCount(parser.LispieValue).init(result_ptr, allocator);
            return result_rc;
        }
    }
}

fn executeFunction(
    function: *parser.LispieValue,
    args: []utils.RefCount(parser.LispieValue),
    module_ctx: *ModuleContext,
    runtime_ctx: utils.RefCount(RuntimeContext),
    allocator: std.mem.Allocator,
) !utils.RefCount(parser.LispieValue) {
    _ = module_ctx;

    // Check if the value passed as function really meets function-value requirements
    if (!switch (function.*) {
        .list => true,
        else => false,
    }) {
        return RuntimeEvaluationError.AttemptedToCallUncallable;
    }
    if (function.list.contents.len != 3) {
        return RuntimeEvaluationError.AttemptedToCallUncallable;
    }

    // Create new scope
    const inner_runtime_ctx_ptr = try allocator.create(RuntimeContext);
    inner_runtime_ctx_ptr.* = .init(allocator);
    inner_runtime_ctx_ptr.outer_ctx = runtime_ctx.clone();
    var inner_runtime_ctx_rc = try utils.RefCount(RuntimeContext).init(inner_runtime_ctx_ptr, allocator);
    defer inner_runtime_ctx_rc.unref();

    const args_def = function.list.contents.items[1].clone();
    defer args_def.unref();
    switch (args_def.value.*) {
        .list => |*args_def_list| {
            for (args_def_list.contents.items, 0..) |arg_name, i| {
                if (!switch (arg_name.value.*) {
                    .symbol => true,
                    else => false,
                }) {
                    return RuntimeEvaluationError.MalformedFunctionArgs;
                }
                (try inner_runtime_ctx_rc.value.bindings.get(arg_name.value.symbol.contents.items, true)).?.* = args[i].clone();
            }
        },
        .symbol => |*args_def_sym| {
            var args_list = std.ArrayList(utils.RefCount(parser.LispieValue)).init(allocator);
            for (args) |arg| {
                try args_list.append(arg);
            }

            const args_list_value_ptr = try allocator.create(parser.LispieValue);
            args_list_value_ptr.* = .{ .list = .{
                .par_type = .normal,
                .prefix = .none,
                .contents = args_list,
            } };
            const args_list_value_rc = try utils.RefCount(parser.LispieValue).init(args_list_value_ptr, allocator);
            (try inner_runtime_ctx_rc.value.bindings.get(args_def_sym.contents.items, true)).?.* = args_list_value_rc;
        },
        else => {},
    }
}
