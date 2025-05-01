const std = @import("std");

const lexer = @import("lexer.zig");

pub const LispieList = struct {
    par_type: lexer.ParenthesisType,
    prefix: lexer.ParenthesisPrefix,
    contents: std.ArrayList(LispieValue),

    pub fn deinit(self: *LispieList) void {
        for (self.contents.items) |*child| {
            child.deinit();
        }
        self.contents.deinit();
    }
};

pub const LispieValue = union(enum) {
    list: LispieList,
    symbol: std.ArrayList(u8),
    number: f64,

    pub fn deinit(self: *LispieValue) void {
        switch (self.*) {
            .list => |*list| {
                list.deinit();
            },
            .symbol => |*sym| {
                sym.deinit();
            },
            else => {},
        }
    }
};

pub const ParseResult = struct {
    val: LispieValue,
    len: usize,

    pub fn deinit(self: *ParseResult) void {
        self.val.deinit();
    }
};

pub fn parse(tokens: []const lexer.Token, allocator: std.mem.Allocator) !ParseResult {
    switch (tokens[0]) {
        .parenthesis => |*par| {
            var children = std.ArrayList(LispieValue).init(allocator);

            var curr_idx: usize = 1;
            while (switch (tokens[curr_idx]) {
                .parenthesis => |*par_next| !par_next.is_right,
                else => true
            }) {
                const child_result = try parse(tokens[curr_idx..], allocator);
                try children.append(child_result.val);
                curr_idx += child_result.len;
            }

            return .{
                .val = .{ .list = .{
                    .par_type = par.par_type,
                    .prefix = par.prefix,
                    .contents = children,
                } },
                .len = curr_idx + 1,
            };
        },
        .symbol => |*sym| {
            // We don't copy sym.* (of type ArrayList(u8)), because it may be freed before the parsing result is used
            // We also don't use clone methods because we might use different allocators
            var symbol_str = std.ArrayList(u8).init(allocator);
            try symbol_str.appendSlice(sym.items);
            return .{ .val = .{ .symbol = symbol_str }, .len = 1 };
        },
        .number_literal => |*num_lit| {
            return .{ .val = .{ .number = num_lit.* }, .len = 1 };
        },
        .string_literal => {
            const str_contents = std.ArrayList(LispieValue).init(allocator);
            return .{
                .val = .{ .list = .{
                    .par_type = .normal,
                    .prefix = .none,
                    .contents = str_contents,
                } },
                .len = 1,
            };
        },
    }
}
