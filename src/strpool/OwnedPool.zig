const std = @import("std");

/// `OwnedPool` is a string interner for internally owned slices.
/// Memory needs to be managed carefully and a copy of the interned map should
/// be extracted.
const OwnedPool = @This();

gpa: std.mem.Allocator,
pool: std.StringArrayHashMap(void),

/// Type safe ID for looking into the `pool` of Strings.
/// Has a limit of 4,294,967,295 so its probably fine for most use cases.
pub const StringID = enum(u32) {
    empty = std.math.maxInt(u32),
    _,
};

pub fn init(gpa: std.mem.Allocator) OwnedPool {
    return .{
        .gpa = gpa,
        .pool = std.StringArrayHashMap(void).init(gpa),
    };
}

pub fn deinit(self: *OwnedPool) void {
    for (self.pool.keys()) |key| {
        self.gpa.free(key);
    }
    self.pool.deinit();
}

pub fn intern(self: *OwnedPool, string: []const u8) !StringID {
    if (string.len == 0) return .empty;

    const gop = try self.pool.getOrPut(string);
    if (!gop.found_existing) {
        gop.key_ptr.* = try self.gpa.dupe(u8, string);
    }

    return @enumFromInt(gop.index);
}

pub fn lookUp(self: *OwnedPool, id: StringID) []const u8 {
    if (id == .empty) return "";
    return self.pool.keys()[@intFromEnum(id)];
}

pub fn copyPool(self: *OwnedPool, gpa: std.mem.Allocator) !std.StringArrayHashMap(void) {
    return try self.pool.cloneWithAllocator(gpa);
}

pub fn drainPool(self: *OwnedPool) std.StringArrayHashMap(void) {
    return self.pool.move();
}

pub fn freePoolKeys(map: *std.StringArrayHashMap(void), gpa: std.mem.Allocator) void {
    for (map.keys()) |key| gpa.free(key);
}

test "test interning" {
    var interner = init(std.testing.allocator);
    defer interner.deinit();

    const id = try interner.intern("hello");
    const lookup = interner.lookUp(id);

    const id_2 = try interner.intern("hello");
    const lookup_2 = interner.lookUp(id_2);

    try std.testing.expectEqualSlices(u8, "hello", lookup);
    try std.testing.expectEqualSlices(u8, lookup, lookup_2);
    try std.testing.expectEqual(id, id_2);
}
