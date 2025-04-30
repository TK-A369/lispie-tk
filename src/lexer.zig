const std = @import("std");
const utils = @import("utils.zig");

const ParenthesisType = enum {
    normal,
    square,
};

const ParenthesisPrefix = enum {
    none,
    quote,
    quasiquote,
    unquote,
    macro_expansion,
};

const Parenthesis = struct {
    par_type: ParenthesisType,
    prefix: ParenthesisPrefix,
    is_right: bool,
};

const Token = union(enum) {
    parenthesis: Parenthesis,
    symbol: std.ArrayList(u8),
    number_literal: f32,
    string_literal: std.ArrayList(u8),
};

pub fn tokenize(code: []const u8, allocator: std.mem.Allocator) !std.ArrayList(Token) {
    var result_tokens: std.ArrayList(Token) = .init(allocator);

    var curr_idx: u32 = 0;
    while (curr_idx < code.len) {
        if (utils.isValueInArray(u8, &[_]u8{ '(', ')', '[', ']' }, code[curr_idx])) {
            try result_tokens.append(.{
                .parenthesis = .{
                    .par_type = if (utils.isValueInArray(u8, &[_]u8{ '(', ')' }, code[curr_idx])) .normal else .square,
                    .prefix = .none,
                    .is_right = false,
                },
            });
        }

        curr_idx += 1;
    }

    return result_tokens;
}
