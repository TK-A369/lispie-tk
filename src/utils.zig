const std = @import("std");

pub fn isValueInArray(comptime T: type, array: []const T, value: T) bool {
    for (array) |elem| {
        if (value == elem) {
            return true;
        }
    }
    return false;
}

pub fn RefCount(comptime T: type) type {
    return struct {
        const Atomic = std.atomic.Value(usize);
        const This = @This();

        count: *Atomic,
        value: *T,
        allocator: std.mem.Allocator,

        pub fn init(value: *T, allocator: std.mem.Allocator) !This {
            const count = try allocator.create(Atomic);
            count.* = .init(1);
            return .{
                .count = count,
                .value = value,
                .allocator = allocator,
            };
        }

        pub fn clone(self: *This) This {
            _ = self.count.fetchAdd(1, .monotonic);
            return .{
                .count = self.count,
                .value = self.value,
                .allocator = self.allocator,
            };
        }

        pub fn unref(self: *This) void {
            if (self.count.fetchSub(1, .release) == 1) {
                _ = self.count.load(.acquire);

                if (std.meta.hasMethod(T, "deinit")) {
                    self.value.deinit();
                    std.debug.print("Deiniting value inside RefCount\n", .{});
                }

                std.debug.print("Destroying {*}\n", .{self.value});
                // std.debug.print("Destroying RefCount\n", .{});

                self.allocator.destroy(self.count);
                self.allocator.destroy(self.value);
            }
        }
    };
}

test "RefCount 1" {
    var allocator = std.testing.allocator;

    const my_value = try allocator.create(i8);
    my_value.* = 7;

    var rc = try RefCount(i8).init(my_value, allocator);

    rc.value.* = 3;

    try std.testing.expectEqual(3, rc.value.*);
    rc.unref();
}

test "RefCount 2" {
    var allocator = std.testing.allocator;

    const my_value = try allocator.create(i8);
    my_value.* = 7;

    var rc = try RefCount(i8).init(my_value, allocator);
    var rc2 = rc.clone();

    rc.value.* = 3;
    rc.unref();

    try std.testing.expectEqual(3, rc2.value.*);
    rc2.unref();
}

pub fn Trie(comptime T: type) type {
    return struct {
        const This = @This();

        pub const Node = struct {
            children: [256]?*Node,
            element: ?*T,
        };

        pub const InorderIterator = struct {
            pub const Pair = struct {
                key: []const u8,
                value: *T,
            };

            const StackFrame = struct {
                node: *Node,
                elem_checked: bool,
                children_checked: i16,
            };

            trie: *This,
            nodes_stack: std.ArrayList(StackFrame),
            key_stack: std.ArrayList(u8),

            pub fn deinit(self: *InorderIterator) void {
                self.nodes_stack.deinit();
                self.key_stack.deinit();
            }

            pub fn next(self: *InorderIterator) !?Pair {
                const curr_frame = &self.nodes_stack.items[self.nodes_stack.items.len - 1];
                if (curr_frame.elem_checked == false) {
                    curr_frame.elem_checked = true;
                    if (curr_frame.node.element) |elem_nonull| {
                        return .{ .key = self.key_stack.items, .value = elem_nonull };
                    }
                }
                while (curr_frame.children_checked < 256) {
                    curr_frame.children_checked += 1;
                    if (curr_frame.node.children[@intCast(curr_frame.children_checked - 1)]) |child_nonull| {
                        try self.key_stack.append(@intCast(curr_frame.children_checked - 1));
                        try self.nodes_stack.append(.{
                            .node = child_nonull,
                            .elem_checked = false,
                            .children_checked = 0,
                        });
                        return self.next();
                    }
                }
                _ = self.nodes_stack.pop();
                _ = self.key_stack.pop();
                if (self.nodes_stack.items.len == 0) {
                    return null;
                }
                return self.next();
            }
        };

        root: *Node,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) !This {
            var children: [256]?*Node = undefined;
            for (&children) |*child| {
                child.* = null;
            }
            const root_ptr = try allocator.create(Node);
            root_ptr.* = .{ .children = children, .element = null };
            return .{
                .root = root_ptr,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *This) void {
            self.deinit_node(self.root);
        }

        pub fn get(self: *This, key: []const u8, create_if_absent: bool) !?*T {
            return get_internal(self, key, self.root, create_if_absent);
        }
        pub fn inorder_iterator(self: *This) !InorderIterator {
            var nodes_stack = std.ArrayList(InorderIterator.StackFrame).init(self.allocator);
            try nodes_stack.append(.{
                .node = self.root,
                .elem_checked = false,
                .children_checked = 0,
            });
            return .{
                .trie = self,
                .nodes_stack = nodes_stack,
                .key_stack = .init(self.allocator),
            };
        }

        fn deinit_node(self: *This, node: *Node) void {
            for (node.children) |child| {
                if (child) |child_nonull| {
                    self.deinit_node(child_nonull);
                }
            }
            if (node.element) |element_nonull| {
                if (std.meta.hasMethod(T, "unref")) {
                    self.value.unref();
                    std.debug.print("Unrefing value inside Trie\n", .{});
                }
                if (std.meta.hasMethod(T, "deinit")) {
                    self.value.deinit();
                    std.debug.print("Deiniting value inside Trie\n", .{});
                }
                self.allocator.destroy(element_nonull);
            }
            self.allocator.destroy(node);
        }

        fn get_internal(self: *This, key: []const u8, node: *Node, create_if_absent: bool) !?*T {
            if (key.len > 0) {
                var child = node.children[key[0]];
                // I believe that right now, there's no better syntax for this
                if (child) |_| {} else {
                    if (create_if_absent) {
                        child = try self.allocator.create(Node);
                        for (&child.?.children) |*subchild| {
                            subchild.* = null;
                        }
                        child.?.element = null;

                        node.children[key[0]] = child;
                    } else {
                        return null;
                    }
                }
                return self.get_internal(key[1..], child.?, create_if_absent);
            } else {
                if (create_if_absent) {
                    if (node.element) |_| {} else {
                        node.element = try self.allocator.create(T);
                    }
                }
                return node.element;
            }
        }
    };
}

test "Trie 1" {
    var trie = try Trie(i32).init(std.testing.allocator);
    defer trie.deinit();

    (try trie.get("abc", true)).?.* = 73;
    (try trie.get("avocado", true)).?.* = 987;

    try std.testing.expectEqual(73, (try trie.get("abc", false)).?.*);
    try std.testing.expectEqual(987, (try trie.get("avocado", false)).?.*);

    try std.testing.expectEqual(987, (try trie.get("avocado", true)).?.*);
    try std.testing.expectEqual(73, (try trie.get("abc", true)).?.*);

    try std.testing.expectEqual(null, (try trie.get("array", false)));
    try std.testing.expectEqual(null, (try trie.get("banana", false)));

    var iter = try trie.inorder_iterator();
    defer iter.deinit();
    while (try iter.next()) |elem| {
        std.debug.print("\"{s}\": {d}\n", .{ elem.key, elem.value.* });
    }
}

test "Trie 2" {
    var trie = try Trie(i32).init(std.testing.allocator);
    defer trie.deinit();

    (try trie.get("abc", true)).?.* = 873;
    (try trie.get("abcdef", true)).?.* = 3;
    (try trie.get("Hello world!", true)).?.* = -5;
    (try trie.get("The quick brown fox jumps over the lazy dog.", true)).?.* = 100;

    var iter = try trie.inorder_iterator();
    defer iter.deinit();
    // while (try iter.next()) |elem| {
    //     std.debug.print("\"{s}\": {d}\n", .{ elem.key, elem.value.* });
    // }
    var p = try iter.next();
    try std.testing.expectEqualStrings("Hello world!", p.?.key);
    try std.testing.expectEqual(-5, p.?.value.*);
    p = try iter.next();
    try std.testing.expectEqualStrings("The quick brown fox jumps over the lazy dog.", p.?.key);
    try std.testing.expectEqual(100, p.?.value.*);
    p = try iter.next();
    try std.testing.expectEqualStrings("abc", p.?.key);
    try std.testing.expectEqual(873, p.?.value.*);
    p = try iter.next();
    try std.testing.expectEqualStrings("abcdef", p.?.key);
    try std.testing.expectEqual(3, p.?.value.*);
    p = try iter.next();
    try std.testing.expectEqual(null, p);
}
