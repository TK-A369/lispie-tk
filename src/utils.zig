const std = @import("std");

pub fn isValueInArray(comptime T: type, array: []const T, value: T) bool {
    for (array) |elem| {
        if (value == elem) {
            return true;
        }
    }
    return false;
}
