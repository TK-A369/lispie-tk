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

        fn deinit_node(self: *This, node: *Node) void {
            for (node.children) |child| {
                if (child) |child_nonull| {
                    self.deinit_node(child_nonull);
                }
            }
            if (node.element) |element_nonull| {
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
}
