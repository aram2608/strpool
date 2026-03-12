const std = @import("std");

/// `Deque` implementation using a `ring-buffer`.
pub fn Deque(comptime T: type) type {
    return struct {
        const Self = @This();

        items: []T,
        capacity: usize,
        head: usize,
        tail: usize,
        len: usize,

        pub const empty: Self = .{
            .items = &.{},
            .capacity = 0,
            .head = 0,
            .tail = 0,
            .len = 0,
        };

        pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            gpa.free(self.allocatedSlice());
        }

        pub fn pushBack(self: *Self, gpa: std.mem.Allocator, item: T) !void {
            const new_len = self.len + 1;
            try self.ensureCapacity(gpa, new_len);

            self.allocatedSlice()[self.tail] = item;
            self.tail = (self.tail + 1) % self.capacity;
            self.len = new_len;
        }

        pub fn pushFront(self: *Self, gpa: std.mem.Allocator, item: T) !void {
            const new_len = self.len + 1;
            try self.ensureCapacity(gpa, new_len);

            const head = (self.head + self.capacity - 1) % self.capacity;

            self.len = new_len;
            self.allocatedSlice()[head] = item;
            self.head = head;
        }

        pub fn popFront(self: *Self) ?T {
            if (self.len == 0) return null;
            const buf = self.allocatedSlice();
            const val = buf[self.head];
            self.head = (self.head + 1) % self.capacity;
            self.len -= 1;
            return val;
        }

        pub fn popBack(self: *Self) ?T {
            if (self.len == 0) return null;
            self.tail = (self.tail + self.capacity - 1) % self.capacity;
            self.len -= 1;
            return self.allocatedSlice()[self.tail];
        }

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
                if (self.head < self.tail) {
                    @memcpy(new_memory[0..self.len], old_memory[self.head..self.tail]);
                } else {
                    const first = old_memory[self.head..];
                    @memcpy(new_memory[0..first.len], first);
                    @memcpy(new_memory[first.len..self.len], old_memory[0..self.tail]);
                }
                gpa.free(old_memory);
                self.items.ptr = new_memory.ptr;
                self.capacity = new_memory.len;
                self.head = 0;
                self.tail = self.len;
            }
        }

        /// Drains the `Deque` and returns the `items` as an owned slice.
        /// The caller is responsible for freeing memory.
        /// The current `Deque` is reset to an `.empty` state.
        pub fn toOwnedSlice(self: *Self, gpa: std.mem.Allocator) ![]T {
            const old_memory = self.allocatedSlice();
            const new_memory = try gpa.alignedAlloc(T, null, self.len);
            if (self.head < self.tail) {
                @memcpy(new_memory[0..self.len], old_memory[self.head..self.tail]);
            } else {
                const first = old_memory[self.head..];
                @memcpy(new_memory[0..first.len], first);
                @memcpy(new_memory[first.len..self.len], old_memory[0..self.tail]);
            }
            gpa.free(old_memory);
            self.* = .empty;
            return new_memory;
        }

        fn allocatedSlice(self: *Self) []T {
            return self.items.ptr[0..self.capacity];
        }
    };
}

test "Deque: pushBack / popFront (queue order)" {
    var dq = Deque(u8).empty;
    defer dq.deinit(std.testing.allocator);

    try dq.pushBack(std.testing.allocator, 1);
    try dq.pushBack(std.testing.allocator, 2);
    try dq.pushBack(std.testing.allocator, 3);

    try std.testing.expectEqual(@as(usize, 3), dq.len);
    try std.testing.expectEqual(@as(?u8, 1), dq.popFront());
    try std.testing.expectEqual(@as(?u8, 2), dq.popFront());
    try std.testing.expectEqual(@as(?u8, 3), dq.popFront());
    try std.testing.expectEqual(@as(?u8, null), dq.popFront());
    try std.testing.expectEqual(@as(usize, 0), dq.len);
}

test "Deque: pushFront / popFront (stack order)" {
    var dq = Deque(u8).empty;
    defer dq.deinit(std.testing.allocator);

    try dq.pushFront(std.testing.allocator, 1);
    try dq.pushFront(std.testing.allocator, 2);
    try dq.pushFront(std.testing.allocator, 3);

    try std.testing.expectEqual(@as(?u8, 3), dq.popFront());
    try std.testing.expectEqual(@as(?u8, 2), dq.popFront());
    try std.testing.expectEqual(@as(?u8, 1), dq.popFront());
    try std.testing.expectEqual(@as(?u8, null), dq.popFront());
}

test "Deque: pushBack / popBack (stack order)" {
    var dq = Deque(u8).empty;
    defer dq.deinit(std.testing.allocator);

    try dq.pushBack(std.testing.allocator, 10);
    try dq.pushBack(std.testing.allocator, 20);
    try dq.pushBack(std.testing.allocator, 30);

    try std.testing.expectEqual(@as(?u8, 30), dq.popBack());
    try std.testing.expectEqual(@as(?u8, 20), dq.popBack());
    try std.testing.expectEqual(@as(?u8, 10), dq.popBack());
    try std.testing.expectEqual(@as(?u8, null), dq.popBack());
    try std.testing.expectEqual(@as(usize, 0), dq.len);
}

test "Deque: mixed pushFront and pushBack" {
    var dq = Deque(u8).empty;
    defer dq.deinit(std.testing.allocator);

    // Build [1, 2, 3, 4] using both ends
    // pushFront(2), pushBack(3), pushFront(1), pushBack(4)
    try dq.pushFront(std.testing.allocator, 2);
    try dq.pushBack(std.testing.allocator, 3);
    try dq.pushFront(std.testing.allocator, 1);
    try dq.pushBack(std.testing.allocator, 4);

    try std.testing.expectEqual(@as(?u8, 1), dq.popFront());
    try std.testing.expectEqual(@as(?u8, 4), dq.popBack());
    try std.testing.expectEqual(@as(?u8, 2), dq.popFront());
    try std.testing.expectEqual(@as(?u8, 3), dq.popBack());
    try std.testing.expectEqual(@as(?u8, null), dq.popFront());
}

test "Deque: wrap-around triggers realloc" {
    var dq = Deque(u32).empty;
    defer dq.deinit(std.testing.allocator);

    // Push enough to force multiple reallocations and wrap the ring buffer.
    var i: u32 = 0;
    while (i < 64) : (i += 1) try dq.pushBack(std.testing.allocator, i);

    // Drain front halfway to move head forward, then fill back up to force wrap.
    var j: u32 = 0;
    while (j < 32) : (j += 1) try std.testing.expectEqual(@as(?u32, j), dq.popFront());

    while (i < 96) : (i += 1) try dq.pushBack(std.testing.allocator, i);

    // Verify remaining items in order.
    var expected: u32 = 32;
    while (dq.popFront()) |val| : (expected += 1) {
        try std.testing.expectEqual(expected, val);
    }
    try std.testing.expectEqual(@as(u32, 96), expected);
}

test "Deque: toOwnedSlice linearizes wrapped buffer" {
    var dq = Deque(u8).empty;

    try dq.pushBack(std.testing.allocator, 1);
    try dq.pushBack(std.testing.allocator, 2);
    try dq.pushBack(std.testing.allocator, 3);
    // advance head for rewrap
    _ = dq.popFront();
    try dq.pushBack(std.testing.allocator, 4);

    const slice = try dq.toOwnedSlice(std.testing.allocator);
    defer std.testing.allocator.free(slice);

    try std.testing.expectEqual(@as(usize, 3), slice.len);
    try std.testing.expectEqual(@as(u8, 2), slice[0]);
    try std.testing.expectEqual(@as(u8, 3), slice[1]);
    try std.testing.expectEqual(@as(u8, 4), slice[2]);
    try std.testing.expectEqual(@as(usize, 0), dq.len);
}
