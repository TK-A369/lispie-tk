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
