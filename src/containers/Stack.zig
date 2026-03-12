const std = @import("std");

/// A `Stack` implementation for any object `T`.
/// A leaner version of std.ArrayList and is likewise unmanaged.
/// Allocation `methods` require an `std.mem.Allocator`.
pub fn Stack(comptime T: type) type {
    return struct {
        const Self = @This();

        items: []T,
        capacity: usize,

        /// Initializes the `Stack` in an empty state.
        pub const empty: Self = .{
            .items = &.{},
            .capacity = 0,
        };

        pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            gpa.free(self.allocatedSlice());
        }

        /// Push a new object of type `T` to the `Stack`.
        /// Allocates the necessary memory for each push.
        pub fn push(self: *Self, gpa: std.mem.Allocator, item: T) !void {
            const new_len = self.items.len + 1;
            try self.ensureCapacity(gpa, new_len);

            self.items.len = new_len;
            self.items[self.items.len - 1] = item;
        }

        /// Pops the final value off the `Stack`.
        /// Returns a `?T` depending on whether or not the `Stack` has any
        /// valid objects.
        /// The allocated memory does not change.
        pub fn pop(self: *Self) ?T {
            if (self.items.len == 0) return null;
            const val = self.items[self.items.len - 1];
            self.items[self.items.len - 1] = undefined;
            self.items.len -= 1;
            return val;
        }

        /// Returns the length of the underlying `items`.
        /// A simple convenience wrapper.
        pub fn len(self: *const Self) usize {
            return self.items.len;
        }

        // Internal helpers.
        // The stack is strictly for pushing and popping values and any fancier
        // use cases should just use a std.ArrayList or std.MultiArrayList.

        fn growCapacity(minimum: usize) usize {
            if (@sizeOf(T) == 0) return std.math.maxInt(usize);
            const init_capacity: comptime_int = @max(1, std.atomic.cache_line / @sizeOf(T));
            return minimum +| (minimum / 2 + init_capacity);
        }

        pub fn ensureCapacity(self: *Self, gpa: std.mem.Allocator, minimum: usize) !void {
            if (@sizeOf(T) == 0) {
                self.capacity = std.math.maxInt(usize);
                return;
            }
            if (self.capacity >= minimum) return;

            // Only calc new cap if capacity is at the minimum.
            const new_cap = growCapacity(minimum);

            // Reallocate memory, unaligned if need be.
            const old_memory = self.allocatedSlice();
            if (gpa.remap(old_memory, new_cap)) |new_memory| {
                self.items.ptr = new_memory.ptr;
                self.capacity = new_memory.len;
            } else {
                const new_memory = try gpa.alignedAlloc(T, null, new_cap);
                @memcpy(new_memory[0..self.items.len], self.items);
                gpa.free(old_memory);
                self.items.ptr = new_memory.ptr;
                self.capacity = new_memory.len;
            }
        }

        /// Reset the `Stack` while leaving allocatable memory intact.
        pub fn clearRetainingCapacity(self: *Self) void {
            self.items.len = 0;
        }

        /// Drains the `Stack` and returns the `items` as an owned slice.
        /// The caller is responsible for freeing memory.
        /// The current `Stack` is reset to an `.empty` state.
        pub fn toOwnedSlice(self: *Self, gpa: std.mem.Allocator) ![]T {
            const result = try gpa.realloc(self.allocatedSlice(), self.items.len);
            self.* = .empty;
            return result;
        }

        fn allocatedSlice(self: *Self) []T {
            return self.items.ptr[0..self.capacity];
        }
    };
}

test "Stack: all ops work" {
    var stack = Stack(u8).empty;
    defer stack.deinit(std.testing.allocator);

    try stack.push(std.testing.allocator, 4);
    try stack.push(std.testing.allocator, 8);
    try stack.push(std.testing.allocator, 15);

    try std.testing.expectEqual(@as(usize, 3), stack.len());
    try std.testing.expectEqual(@as(?u8, 15), stack.pop());
    try std.testing.expectEqual(@as(?u8, 8), stack.pop());
    try std.testing.expectEqual(@as(usize, 1), stack.len());

    // empty pop should return null
    _ = stack.pop();
    _ = stack.pop();
    try std.testing.expectEqual(@as(?u8, null), stack.pop());

    try stack.push(std.testing.allocator, 4);
    try stack.push(std.testing.allocator, 4);
    try stack.push(std.testing.allocator, 4);

    const slice = try stack.toOwnedSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);

    try std.testing.expect(stack.len() == 0);
    try std.testing.expectEqual(@as(u8, 4), slice[0]);
}
