const std = @import("std");

const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const utils = @import("utils.zig");

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    var da = std.heap.DebugAllocator(.{}).init;
    const allocator = da.allocator();
    defer _ = da.deinit();

    const code =
        \\(print
        \\  "3 + 4 = "
        \\  (add
        \\    3
        \\    4))
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

    var parse_result_str = try parse_result.val.toString(0, allocator);
    defer parse_result_str.deinit();
    try stdout.print("Parse result:\n{s}\n", .{parse_result_str.items});

    try bw.flush(); // Don't forget to flush!
}

comptime {
    _ = utils;
}
