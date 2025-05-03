const std = @import("std");
const utils = @import("utils.zig");

pub const ParenthesisType = enum {
    normal,
    square,
};

pub const ParenthesisPrefix = enum {
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
    number_literal: f64,
    string_literal: std.ArrayList(u8),

    pub fn deinit(self: *Token) void {
        switch (self.*) {
            .symbol => |*sym| {
                sym.deinit();
            },
            .string_literal => |*str| {
                str.deinit();
            },
            else => {}
        }
    }

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
                try std.fmt.format(result_writer, "NumberLiteral({d})", .{num.*});
            },
            .string_literal => |*str| {
                try std.fmt.format(result_writer, "StringLiteral(\"{s}\")", .{str.items});
            },
        }

        return result;
    }
};

pub const LexerError = error{
    UnexpectedEOF,
};

pub fn tokenize(code: []const u8, allocator: std.mem.Allocator) !std.ArrayList(Token) {
    var result_tokens: std.ArrayList(Token) = .init(allocator);

    var curr_idx: u32 = 0;
    while (curr_idx < code.len) {
        // std.debug.print("curr_idx = {d}\n", .{curr_idx});

        if (std.ascii.isWhitespace(code[curr_idx])) {
            curr_idx += 1;
        } else if (utils.isValueInArray(u8, &[_]u8{ '(', ')', '[', ']', '\'', '`', ',', '!' }, code[curr_idx])) {
            // Parentheses
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
            //Symbols
            var symbol_str = std.ArrayList(u8).init(allocator);
            while (std.ascii.isAlphabetic(code[curr_idx])) {
                try symbol_str.append(code[curr_idx]);
                curr_idx += 1;
            }

            try result_tokens.append(.{
                .symbol = symbol_str,
            });
        } else if (std.ascii.isDigit(code[curr_idx]) or utils.isValueInArray(u8, &[_]u8{ '+', '-' }, code[curr_idx])) {
            // Number literals
            var negative = false;
            if (code[curr_idx] == '+') {
                curr_idx += 1;
            } else if (code[curr_idx] == '-') {
                negative = true;
                curr_idx += 1;
            }
            if (curr_idx >= code.len) {
                return error.UnexpectedEOF;
            }

            var integer_part = std.ArrayList(u8).init(allocator);
            defer integer_part.deinit();
            while (std.ascii.isDigit(code[curr_idx])) {
                try integer_part.append(code[curr_idx]);
                curr_idx += 1;
            }

            var num_value: f64 = 0.0;
            for (integer_part.items, 0..) |digit, i| {
                num_value += std.math.pow(f64, 10.0, @as(f64, @floatFromInt(@as(i32, @intCast(integer_part.items.len - i)) - 1))) * @as(f64, @floatFromInt(digit - '0'));
            }

            if (code[curr_idx] == '.') {
                curr_idx += 1;

                var fraction_part = std.ArrayList(u8).init(allocator);
                defer fraction_part.deinit();

                while (std.ascii.isDigit(code[curr_idx])) {
                    try fraction_part.append(code[curr_idx]);
                    curr_idx += 1;
                }

                for (fraction_part.items, 0..) |digit, i| {
                    num_value += std.math.pow(f64, 10.0, @as(f64, @floatFromInt(-1 - @as(i32, @intCast(i))))) * @as(f64, @floatFromInt(digit - '0'));
                }
            }

            if (negative) {
                num_value = -num_value;
            }

            try result_tokens.append(.{
                .number_literal = num_value,
            });
        } else if (code[curr_idx] == '\"') {
            //String literals
            var str_content = std.ArrayList(u8).init(allocator);
            curr_idx += 1;
            while (code[curr_idx] != '\"') {
                if (code[curr_idx] == '\\') {
                    switch (code[curr_idx + 1]) {
                        'n' => {
                            try str_content.append('\n');
                        },
                        '\"' => {
                            try str_content.append('\"');
                        },
                        else => {}
                    }
                    curr_idx += 2;
                } else {
                    try str_content.append(code[curr_idx]);
                    curr_idx += 1;
                }
            }
            curr_idx += 1;

            try result_tokens.append(.{ .string_literal = str_content });
        }
    }

    return result_tokens;
}
