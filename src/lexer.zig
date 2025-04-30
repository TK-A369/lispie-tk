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

pub const Token = union(enum) {
    parenthesis: Parenthesis,
    symbol: std.ArrayList(u8),
    number_literal: f32,
    string_literal: std.ArrayList(u8),

    pub fn toString(self: *const Token, allocator: std.mem.Allocator) !std.ArrayList(u8) {
        var result = std.ArrayList(u8).init(allocator);
        const result_writer = result.writer();
        switch (self.*) {
            .parenthesis => |*par| {
                try std.fmt.format(result_writer, "Parenthesis({s}, {s}, {s})", .{
                    if (par.par_type == .normal) "normal" else "square",
                    switch (par.prefix) {
                        .none => "none",
                        .quote => "quote",
                        .quasiquote => "quasiquote",
                        .unquote => "unquote",
                        .macro_expansion => "macro_expansion",
                    },
                    if (par.is_right) "right" else "left",
                });
            },
            .symbol => |*sym| {
                try std.fmt.format(result_writer, "Symbol(\"{s}\")", .{sym.items});
            },
            .number_literal => |*num| {
                try std.fmt.format(result_writer, "NumberLiteral({d})", .{num});
            },
            .string_literal => |*str| {
                try std.fmt.format(result_writer, "StringLiteral(\"{s}\")", .{str.items});
            },
        }

        return result;
    }
};

pub fn tokenize(code: []const u8, allocator: std.mem.Allocator) !std.ArrayList(Token) {
    var result_tokens: std.ArrayList(Token) = .init(allocator);

    var curr_idx: u32 = 0;
    while (curr_idx < code.len) {
        // Parentheses
        if (utils.isValueInArray(u8, &[_]u8{ '(', ')', '[', ']', '\'', '`', ',', '!' }, code[curr_idx])) {
            var prefix: ParenthesisPrefix = .none;
            if (utils.isValueInArray(u8, &[_]u8{ '\'', '`', ',', '!' }, code[curr_idx]) and curr_idx < code.len - 1) {
                switch (code[curr_idx]) {
                    '\'' => {
                        prefix = .quote;
                    },
                    '`' => {
                        prefix = .quasiquote;
                    },
                    ',' => {
                        prefix = .unquote;
                    },
                    '!' => {
                        prefix = .macro_expansion;
                    },
                    else => {}
                }
                curr_idx += 1;
            }

            try result_tokens.append(.{
                .parenthesis = .{
                    .par_type = if (utils.isValueInArray(u8, &[_]u8{ '(', ')' }, code[curr_idx])) .normal else .square,
                    .prefix = prefix,
                    .is_right = utils.isValueInArray(u8, &[_]u8{ ')', ']' }, code[curr_idx]),
                },
            });
            curr_idx += 1;
        } else if (std.ascii.isAlphabetic(code[curr_idx])) {
            var symbol_str = std.ArrayList(u8).init(allocator);
            while (std.ascii.isAlphabetic(code[curr_idx])) {
                try symbol_str.append(code[curr_idx]);
            }

            try result_tokens.append(.{
                .symbol = symbol_str,
            });
        }
    }

    return result_tokens;
}
