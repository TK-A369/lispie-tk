const std = @import("std");

const utils = @import("utils.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const evaluator = @import("evaluator.zig");

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var da = std.heap.DebugAllocator(.{}).init;
    const allocator = da.allocator();
    defer _ = da.deinit();

    const code =
        \\(do
        \\  (defmacro mymacro [f a b] `(do (,f ,a) (,f ,b)))
        \\  (print
        \\    "3 + 4 = "
        \\    (add
        \\      3
        \\      4)))
    ;
    try stdout.print("Code:\n\"\"\"\n{s}\n\"\"\"\n", .{code});
    const tokens = try lexer.tokenize(code, allocator);
    defer tokens.deinit();
    defer {
        for (tokens.items) |*tok| {
            tok.deinit();
        }
    }
    try stdout.print("Tokens count: {d}\n", .{tokens.items.len});

    for (tokens.items) |tok| {
        var token_str = try tok.toString(allocator);
        defer token_str.deinit();
        try stdout.print("Token: {s}\n", .{token_str.items});
    }

    var parse_result = try parser.parse(tokens.items, allocator);
    defer parse_result.deinit();

    var parse_result_str = try parse_result.val.value.toString(0, allocator);
    defer parse_result_str.deinit();
    try stdout.print("Parse result:\n{s}\n", .{parse_result_str.items});

    var module_ctx = try evaluator.ModuleContext.init(allocator);
    defer module_ctx.deinit();
    var macro_read_result = try evaluator.evaluateReadMacros(parse_result.val.value, &module_ctx, allocator);
    defer macro_read_result.unref();

    var macro_read_result_str = try macro_read_result.value.toString(0, allocator);
    defer macro_read_result_str.deinit();
    try stdout.print("Macro read result:\n{s}\n", .{macro_read_result_str.items});

    var macro_iter = try module_ctx.macros.inorderIterator();
    defer macro_iter.deinit();
    while (try macro_iter.next()) |macro| {
        var macro_args_str = try macro.value.args.value.toString(0, allocator);
        defer macro_args_str.deinit();
        var macro_body_str = try macro.value.body.value.toString(0, allocator);
        defer macro_body_str.deinit();
        try stdout.print("Macro {s}:\nArgs:\n{s}\nBody:\n{s}\n\n", .{ macro.key, macro_args_str.items, macro_body_str.items });
    }

    try bw.flush(); // Don't forget to flush!
}

comptime {
    _ = utils;
}
