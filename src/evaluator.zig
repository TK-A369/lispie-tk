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
            .bindings = try .init(allocator),
            .outer_ctx = null,
        };
    }

    pub fn deinit(self: *RuntimeContext) void {
        self.bindings.deinit();
        if (self.outer_ctx) |*outer_ctx_nonull| {
            outer_ctx_nonull.unref();
        }
    }

    pub fn get_binding(self: *RuntimeContext, name: []const u8) !?utils.RefCount(parser.LispieValue) {
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
    MalformedLet,
    MalformedSyscall,
    UnknownSyscall,
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

                std.debug.print("Macro {s} defined\n", .{macro_name_sym.contents.items});

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
    std.debug.print("evaluateRuntime called!\n", .{});

    switch (value.*) {
        .list => |*list| {
            // Quotelists will remain unchanged, only the quote prefix will be removed
            if (list.prefix == .quote) {
                std.debug.print("Quotelist is being evaluated!\n", .{});

                const result_ptr = try allocator.create(parser.LispieValue);
                result_ptr.* = try value.clone(allocator);
                result_ptr.list.prefix = .none;
                const result_rc = try utils.RefCount(parser.LispieValue).init(result_ptr, allocator);
                return result_rc;
            }

            if (list.contents.items.len < 1) {
                return RuntimeEvaluationError.EmptyCall;
            }

            // Check if this is special form call
            switch (list.contents.items[0].value.*) {
                .symbol => |*special_form_sym| {
                    if (std.mem.eql(u8, special_form_sym.contents.items, "let")) {
                        std.debug.print("`let` special form is being evaluated!\n", .{});

                        var runtime_ctx_mut = runtime_ctx;
                        const inner_runtime_ctx_ptr = try allocator.create(RuntimeContext);
                        inner_runtime_ctx_ptr.* = try .init(allocator);
                        inner_runtime_ctx_ptr.outer_ctx = runtime_ctx_mut.clone();
                        var inner_runtime_ctx_rc = try utils.RefCount(RuntimeContext).init(inner_runtime_ctx_ptr, allocator);
                        defer inner_runtime_ctx_rc.unref();

                        for (0..(list.contents.items.len - 2)) |i| {
                            // Check if binding definition is correct
                            switch (list.contents.items[i + 1].value.*) {
                                .list => |*binding_def_list| {
                                    switch (binding_def_list.contents.items[0].value.*) {
                                        .symbol => {},
                                        else => {
                                            return RuntimeEvaluationError.MalformedLet;
                                        }
                                    }
                                },
                                else => {
                                    return RuntimeEvaluationError.MalformedLet;
                                }
                            }

                            const binding_value_evaluated = try evaluateRuntime(list.contents.items[i + 1].value.list.contents.items[1].value, module_ctx, inner_runtime_ctx_rc, allocator);

                            (try inner_runtime_ctx_rc.value.bindings.get(
                                list.contents.items[i + 1].value.list.contents.items[0].value.symbol.contents.items,
                                true,
                            )).?.* = binding_value_evaluated;
                        }

                        return try evaluateRuntime(
                            list.contents.items[list.contents.items.len - 1].value,
                            module_ctx,
                            inner_runtime_ctx_rc,
                            allocator,
                        );
                    } else if (std.mem.eql(u8, special_form_sym.contents.items, "do")) {
                        std.debug.print("`do` special form is being evaluated!\n", .{});

                        for (0..(list.contents.items.len - 1)) |i| {
                            var child_eval_result = try evaluateRuntime(
                                list.contents.items[i + 1].value,
                                module_ctx,
                                runtime_ctx,
                                allocator,
                            );
                            defer child_eval_result.unref();
                            if (i == list.contents.items.len - 2) {
                                return child_eval_result.clone();
                            }
                        }
                    } else if (std.mem.eql(u8, special_form_sym.contents.items, "syscall")) {
                        std.debug.print("`syscall` special form is being evaluated!\n", .{});

                        var args = std.ArrayList(utils.RefCount(parser.LispieValue)).init(allocator);
                        defer {
                            for (args.items) |*arg| {
                                arg.unref();
                            }
                            args.deinit();
                        }
                        try args.append(list.contents.items[1].clone());

                        for (list.contents.items[2..]) |arg| {
                            try args.append(try evaluateRuntime(arg.value, module_ctx, runtime_ctx, allocator));
                        }

                        // return makeEmptyList(allocator);
                        return executeSyscall(args.items, allocator);
                    } else if (std.mem.eql(u8, special_form_sym.contents.items, "defmacro")) {
                        return makeEmptyList(allocator);
                    }
                },
                else => {}
            }

            var function_evaluated = try evaluateRuntime(
                list.contents.items[0].value,
                module_ctx,
                runtime_ctx,
                allocator,
            );
            defer function_evaluated.unref();

            var args_evaluated = std.ArrayList(utils.RefCount(parser.LispieValue)).init(allocator);
            for (1..list.contents.items.len) |i| {
                try args_evaluated.append(try evaluateRuntime(
                    list.contents.items[i].value,
                    module_ctx,
                    runtime_ctx,
                    allocator,
                ));
            }
            defer {
                for (args_evaluated.items) |*ae| {
                    ae.unref();
                }
            }

            return try executeFunction(function_evaluated.value, args_evaluated.items, module_ctx, runtime_ctx, allocator);
        },
        .symbol => |*sym| {
            const binding_value = try runtime_ctx.value.get_binding(sym.contents.items);
            if (binding_value) |binding_value_nonull| {
                return binding_value_nonull;
            }

            return makeEmptyList(allocator);
        },
        else => {
            const result_ptr = try allocator.create(parser.LispieValue);
            result_ptr.* = try value.clone(allocator);
            const result_rc = try utils.RefCount(parser.LispieValue).init(result_ptr, allocator);
            return result_rc;
        }
    }
}

pub fn evaluate(
    value: *parser.LispieValue,
    module_ctx: *ModuleContext,
    allocator: std.mem.Allocator,
    debug_prints: bool,
) !utils.RefCount(parser.LispieValue) {
    var macro_read_result = try evaluateReadMacros(value, module_ctx, allocator);
    defer macro_read_result.unref();

    if (debug_prints) {
        var macro_read_result_str = try macro_read_result.value.toString(0, allocator);
        defer macro_read_result_str.deinit();
        std.debug.print("Macro read result:\n{s}\n", .{macro_read_result_str.items});
    }

    var macro_expand_result = try evaluateExpandMacros(macro_read_result.value, module_ctx, allocator);
    defer macro_expand_result.unref();

    if (debug_prints) {
        var macro_expand_result_str = try macro_expand_result.value.toString(0, allocator);
        defer macro_expand_result_str.deinit();
        std.debug.print("Macro expand result:\n{s}\n", .{macro_expand_result_str.items});
    }

    const runtime_ctx_ptr = try allocator.create(RuntimeContext);
    runtime_ctx_ptr.* = try .init(allocator);
    var runtime_ctx_rc = try utils.RefCount(RuntimeContext).init(runtime_ctx_ptr, allocator);
    defer runtime_ctx_rc.unref();

    const runtime_evaluation_result = try evaluateRuntime(
        macro_expand_result.value,
        module_ctx,
        runtime_ctx_rc,
        allocator,
    );

    if (debug_prints) {
        var eval_result_str = try runtime_evaluation_result.value.toString(0, allocator);
        defer eval_result_str.deinit();
        std.debug.print("Evaluation result:\n{s}\n", .{eval_result_str.items});
    }

    return runtime_evaluation_result;
}

fn makeEmptyList(allocator: std.mem.Allocator) !utils.RefCount(parser.LispieValue) {
    const result_ptr = try allocator.create(parser.LispieValue);
    result_ptr.* = .{ .list = .{
        .par_type = .normal,
        .prefix = .none,
        .contents = .init(allocator),
    } };
    const result_rc = try utils.RefCount(parser.LispieValue).init(result_ptr, allocator);
    return result_rc;
}

fn executeFunction(
    function: *parser.LispieValue,
    args: []utils.RefCount(parser.LispieValue),
    module_ctx: *ModuleContext,
    runtime_ctx: utils.RefCount(RuntimeContext),
    allocator: std.mem.Allocator,
) (RuntimeEvaluationError || error{OutOfMemory})!utils.RefCount(parser.LispieValue) {
    std.debug.print("Function call is being evaluated!\n", .{});

    // Check if the value passed as function really meets function-value requirements
    if (!switch (function.*) {
        .list => true,
        else => false,
    }) {
        return RuntimeEvaluationError.UncallableCallAttempt;
    }
    if (function.list.contents.items.len != 3) {
        return RuntimeEvaluationError.UncallableCallAttempt;
    }

    // Create new scope
    var runtime_ctx_mut = runtime_ctx;
    const inner_runtime_ctx_ptr = try allocator.create(RuntimeContext);
    inner_runtime_ctx_ptr.* = try .init(allocator);
    inner_runtime_ctx_ptr.outer_ctx = runtime_ctx_mut.clone();
    var inner_runtime_ctx_rc = try utils.RefCount(RuntimeContext).init(inner_runtime_ctx_ptr, allocator);
    defer inner_runtime_ctx_rc.unref();

    var args_def = function.list.contents.items[1].clone();
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

    var function_body = function.list.contents.items[2].clone();
    defer function_body.unref();

    return try evaluateRuntime(function_body.value, module_ctx, inner_runtime_ctx_rc, allocator);
}

fn executeSyscall(
    args: []utils.RefCount(parser.LispieValue),
    allocator: std.mem.Allocator,
) !utils.RefCount(parser.LispieValue) {
    if (args.len < 1) {
        return RuntimeEvaluationError.MalformedSyscall;
    }
    switch (args[0].value.*) {
        .symbol => |*sym| {
            if (std.mem.eql(u8, sym.contents.items, "print")) {
                for (args[1..]) |arg| {
                    switch (arg.value.*) {
                        .list => |*str_list| {
                            for (str_list.contents.items) |*str_char| {
                                switch (str_char.value.*) {
                                    .number => |*str_char_code| {
                                        //TODO: Use stdout instead of stderr
                                        std.debug.print("{c}", .{@as(u8, @intFromFloat(str_char_code.*))});
                                    },
                                    else => {
                                        return RuntimeEvaluationError.MalformedSyscall;
                                    }
                                }
                            }
                        },
                        .number => |*str_char_code| {
                            //TODO: Use stdout instead of stderr
                            std.debug.print("{c}", .{@as(u8, @intFromFloat(str_char_code.*))});
                        },
                        else => {
                            return RuntimeEvaluationError.MalformedSyscall;
                        }
                    }
                }
                return makeEmptyList(allocator);
            } else if (std.mem.eql(u8, sym.contents.items, "add")) {
                // TODO
                return makeEmptyList(allocator);
            } else {
                return RuntimeEvaluationError.UnknownSyscall;
            }
        },
        else => {}
    }
    return RuntimeEvaluationError.MalformedSyscall;
}
