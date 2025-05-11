const std = @import("std");

const utils = @import("utils.zig");
const lexer = @import("lexer.zig");

pub const LispieList = struct {
    par_type: lexer.ParenthesisType,
    prefix: lexer.ParenthesisPrefix,
    contents: std.ArrayList(utils.RefCount(LispieValue)),

    pub fn deinit(self: *LispieList) void {
        for (self.contents.items) |*child| {
            child.unref();
        }
        self.contents.deinit();
    }

    pub fn clone(self: *LispieList, allocator: std.mem.Allocator) !LispieList {
        var clone_contents = std.ArrayList(utils.RefCount(LispieValue)).init(allocator);
        for (self.contents.items) |*child| {
            try clone_contents.append(child.clone());
        }
        return .{
            .par_type = self.par_type,
            .prefix = self.prefix,
            .contents = clone_contents,
        };
    }
};

pub const LispieSymbol = struct {
    prefix: lexer.ParenthesisPrefix,
    contents: std.ArrayList(u8),

    pub fn deinit(self: *LispieSymbol) void {
        self.contents.deinit();
    }

    pub fn clone(self: *LispieSymbol, allocator: std.mem.Allocator) !LispieSymbol {
        var clone_contents = std.ArrayList(u8).init(allocator);
        for (self.contents.items) |*ch| {
            try clone_contents.append(ch.*);
        }
        return .{
            .prefix = self.prefix,
            .contents = clone_contents,
        };
    }
};

pub const LispieValue = union(enum) {
    list: LispieList,
    symbol: LispieSymbol,
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

    pub fn clone(self: *LispieValue, allocator: std.mem.Allocator) !LispieValue {
        switch (self.*) {
            .list => |*list| {
                return .{
                    .list = try list.clone(allocator),
                };
            },
            .symbol => |*sym| {
                return .{
                    .symbol = try sym.clone(allocator),
                };
            },
            else => {
                return self.*;
            }
        }
    }

    pub fn toString(self: *const LispieValue, depth: u32, allocator: std.mem.Allocator) !std.ArrayList(u8) {
        var result = std.ArrayList(u8).init(allocator);
        const result_writer = result.writer();
        switch (self.*) {
            .list => |*list| {
                for (0..depth) |i| {
                    _ = i;
                    try result_writer.writeAll("  ");
                }
                switch (list.prefix) {
                    .none => try result_writer.writeAll(""),
                    .quote => try result_writer.writeAll("\'"),
                    .quasiquote => try result_writer.writeAll("`"),
                    .unquote => try result_writer.writeAll(","),
                    .macro_expansion => try result_writer.writeAll("!"),
                }
                switch (list.par_type) {
                    .normal => try result_writer.writeAll("(\n"),
                    .square => try result_writer.writeAll("[\n"),
                }

                for (list.contents.items) |child| {
                    var child_str = try child.value.toString(depth + 1, allocator);
                    defer child_str.deinit();

                    try std.fmt.format(result_writer, "{s}\n", .{child_str.items});
                }

                for (0..depth) |i| {
                    _ = i;
                    try result_writer.writeAll("  ");
                }
                switch (list.par_type) {
                    .normal => try result_writer.writeAll(")"),
                    .square => try result_writer.writeAll("]"),
                }
            },
            .symbol => |*sym| {
                for (0..depth) |i| {
                    _ = i;
                    try result_writer.writeAll("  ");
                }
                switch (sym.prefix) {
                    .none => try result_writer.writeAll(""),
                    .quote => try result_writer.writeAll("\'"),
                    .quasiquote => try result_writer.writeAll("`"),
                    .unquote => try result_writer.writeAll(","),
                    .macro_expansion => try result_writer.writeAll("!"),
                }

                try std.fmt.format(result_writer, "{s}", .{sym.contents.items});
            },
            .number => |*num| {
                for (0..depth) |i| {
                    _ = i;
                    try result_writer.writeAll("  ");
                }
                try std.fmt.format(result_writer, "{d}", .{num.*});
            },
        }

        return result;
    }
};

pub const ParseResult = struct {
    val: utils.RefCount(LispieValue),
    len: usize,

    pub fn deinit(self: *ParseResult) void {
        self.val.unref();
    }
};

pub fn parse(tokens: []const lexer.Token, allocator: std.mem.Allocator) !ParseResult {
    switch (tokens[0]) {
        .parenthesis => |*par| {
            var children = std.ArrayList(utils.RefCount(LispieValue)).init(allocator);

            var curr_idx: usize = 1;
            while (switch (tokens[curr_idx]) {
                .parenthesis => |*par_next| !par_next.is_right,
                else => true
            }) {
                var child_result = try parse(tokens[curr_idx..], allocator);
                defer child_result.deinit();

                try children.append(child_result.val.clone());
                curr_idx += child_result.len;
            }

            const list_value_ptr = try allocator.create(LispieValue);
            list_value_ptr.* = .{ .list = .{
                .par_type = par.par_type,
                .prefix = par.prefix,
                .contents = children,
            } };
            const list_value_rc = try utils.RefCount(LispieValue).init(list_value_ptr, allocator);

            return .{
                .val = list_value_rc,
                .len = curr_idx + 1,
            };
        },
        .symbol => |*sym| {
            // We don't copy sym.* (of type ArrayList(u8)), because it may be freed before the parsing result is used
            // We also don't use clone methods because we might use different allocators
            var symbol_str = std.ArrayList(u8).init(allocator);
            try symbol_str.appendSlice(sym.contents.items);

            const sym_value_ptr = try allocator.create(LispieValue);
            sym_value_ptr.* = .{ .symbol = .{
                .prefix = sym.prefix,
                .contents = symbol_str,
            } };
            const sym_value_rc = try utils.RefCount(LispieValue).init(sym_value_ptr, allocator);

            return .{
                .val = sym_value_rc,
                .len = 1,
            };
        },
        .number_literal => |*num_lit| {
            const num_value_ptr = try allocator.create(LispieValue);
            num_value_ptr.* = .{ .number = num_lit.* };
            const num_value_rc = try utils.RefCount(LispieValue).init(num_value_ptr, allocator);

            return .{
                .val = num_value_rc,
                .len = 1,
            };
        },
        .string_literal => |*str_lit| {
            var str_contents = std.ArrayList(utils.RefCount(LispieValue)).init(allocator);
            for (str_lit.items) |ch| {
                const char_value_ptr = try allocator.create(LispieValue);
                char_value_ptr.* = .{ .number = @floatFromInt(ch) };
                const char_value_rc = try utils.RefCount(LispieValue).init(char_value_ptr, allocator);

                try str_contents.append(char_value_rc);
            }

            const str_value_ptr = try allocator.create(LispieValue);
            str_value_ptr.* = .{ .list = .{
                .par_type = .normal,
                .prefix = .quote,
                .contents = str_contents,
            } };
            const str_value_rc = try utils.RefCount(LispieValue).init(str_value_ptr, allocator);

            return .{
                .val = str_value_rc,
                .len = 1,
            };
        },
    }
}
