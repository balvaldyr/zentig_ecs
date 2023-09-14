const std = @import("std");
const builtin = @import("builtin");
const ztg = @import("init.zig");
const util = @import("util.zig");
const ByteArray = @import("etc/byte_array.zig");
const Allocator = std.mem.Allocator;

/// Stores component data as bytes on the heap
pub fn ComponentArray(comptime Index: type) type {
    return struct {
        const Self = @This();

        component_id: util.CompId,
        component_name: if (builtin.mode == .Debug) []const u8 else void,

        components_data: ByteArray,
        entities: std.ArrayListUnmanaged(ztg.Entity) = .{},
        ent_to_comp_idx: std.AutoHashMapUnmanaged(ztg.Entity, Index) = .{},

        pub fn init(comptime T: type) Self {
            //const max_cap = comptime blk: {
            //    if (std.meta.trait.isContainer(T) and @hasDecl(T, "max_entities")) break :blk T.max_entities;
            //    break :blk max_ents;
            //};
            //_ = max_cap;

            var self = Self{
                .component_id = util.compId(T),
                .component_name = if (builtin.mode == .Debug) @typeName(T) else void{},
                .components_data = ByteArray.init(T),
            };

            return self;
        }

        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            self.components_data.deinit(alloc);
            self.entities.deinit(alloc);
            self.ent_to_comp_idx.deinit(alloc);
        }

        pub fn assign(self: *Self, alloc: std.mem.Allocator, ent: ztg.Entity, entry: anytype) !void {
            self.assertType(@TypeOf(entry));
            try self.appendBytes(alloc, ent, std.mem.asBytes(&entry));
        }

        pub fn assignData(self: *Self, alloc: std.mem.Allocator, ent: ztg.Entity, data: *const anyopaque) !void {
            try self.appendBytes(alloc, ent, data);
        }

        fn appendBytes(self: *Self, alloc: std.mem.Allocator, ent: ztg.Entity, bytes_start: *const anyopaque) !void {
            try self.entities.append(alloc, ent);
            try self.ent_to_comp_idx.put(alloc, ent, @intCast(self.components_data.len));
            try self.components_data.appendPtr(alloc, bytes_start);
        }

        pub fn willResize(self: *const Self) bool {
            return self.entities.items.len >= self.components_data.getCapacity();
        }

        pub fn reassign(self: *Self, old: ztg.Entity, new: ztg.Entity) void {
            const old_ent_idx = self.indexOfEntityInEnts(old);
            self.entities.items[old_ent_idx] = new;
            const comp_idx = self.ent_to_comp_idx.get(old).?;
            _ = self.ent_to_comp_idx.remove(old);
            self.ent_to_comp_idx.putAssumeCapacity(new, comp_idx);
        }

        pub fn swapRemove(self: *Self, ent: ztg.Entity) void {
            const last_ent = self.entities.items[self.entities.items.len - 1];

            // here because the entities array mirrors the components array,
            // (whenever an entity is added at an index, a component is added at the same index in the component array)
            // wherever the entity is removed at is where the component data will be swapRemove'ed into...
            const index_of_rem = self.indexOfEntityInEnts(ent);
            _ = self.entities.swapRemove(index_of_rem);

            self.components_data.swapRemove(self.ent_to_comp_idx.get(ent).?);
            _ = self.ent_to_comp_idx.remove(ent);

            // were removing the end of the array, so no need to reassign the last_ent's value
            if (index_of_rem == self.entities.items.len) return;

            // ... so we can assign that here
            self.ent_to_comp_idx.putAssumeCapacity(last_ent, @intCast(index_of_rem));
        }

        fn indexOfEntityInEnts(self: *const Self, ent: ztg.Entity) usize {
            // since entities and components are always added in pairs,
            // ent_to_comp_idx also functions as an ent_to_ent_idx
            return self.ent_to_comp_idx.get(ent) orelse std.debug.panic("Could not find entity {} in entities.", .{ent});
        }

        pub fn get(self: *const Self, ent: ztg.Entity) ?*anyopaque {
            const index = self.ent_to_comp_idx.get(ent) orelse return null;
            return self.components_data.get(index);
        }

        pub fn getAs(self: *const Self, comptime T: type, ent: ztg.Entity) ?*T {
            self.assertType(T);

            var g = self.get(ent) orelse return null;
            return cast(T, g);
        }

        pub inline fn contains(self: *const Self, ent: ztg.Entity) bool {
            return self.ent_to_comp_idx.contains(ent);
        }

        pub inline fn len(self: *const Self) usize {
            return self.entities.items.len;
        }

        inline fn cast(comptime T: type, data: *anyopaque) *T {
            if (@alignOf(T) == 0) return @ptrCast(data);
            return @ptrCast(@alignCast(data));
        }

        pub fn iterator(self: *Self) ByteArray.ByteIterator {
            return self.components_data.iterator();
        }

        fn assertType(self: Self, comptime T: type) void {
            if (util.compId(T) != self.component_id) switch (builtin.mode) {
                .Debug => std.debug.panic("Incorrect type. Expected Type: {s} (ID {}), found Type {s} (ID: {}).", .{
                    self.component_name,
                    self.component_id,
                    @typeName(T),
                    util.compId(T),
                }),
                else => std.debug.panic("Type {s} is not correct for component array.", .{@typeName(T)}),
            };
        }
    };
}

fn initForTests(comptime Index: type, comptime T: type) ComponentArray(Index) {
    return ComponentArray(Index).init(T);
}

const Data = struct {
    val: u32,
    uhh: bool = false,
    xd: f32 = 100.0,
    ugh: enum { ok, bad } = .ok,
};

test "simple test" {
    var arr = initForTests(usize, u32);
    defer arr.deinit(std.testing.allocator);

    try arr.assign(std.testing.allocator, 0, @as(u32, 1));
    try arr.assign(std.testing.allocator, 1, @as(u32, 1));
    try arr.assign(std.testing.allocator, 2, @as(u32, 1));

    _ = arr.swapRemove(2);

    for (arr.components_data.slicedAs(u32)) |val| {
        try std.testing.expectEqual(@as(u32, 1), val);
    }
}

test "data" {
    var arr = initForTests(usize, Data);
    defer arr.deinit(std.testing.allocator);

    try arr.assign(std.testing.allocator, 2, Data{ .val = 100_000 });
    try arr.assignData(std.testing.allocator, 5, &Data{ .val = 20_000 });

    try std.testing.expectEqual(@as(u32, 100_000), arr.getAs(Data, 2).?.val);
    try std.testing.expectEqual(@as(u32, 20_000), arr.getAs(Data, 5).?.val);

    try std.testing.expect(arr.contains(2));
    arr.swapRemove(2);
    try std.testing.expect(!arr.contains(2));

    try std.testing.expectEqual(@as(f32, 100.0), arr.getAs(Data, 5).?.xd);

    arr.swapRemove(5);

    try std.testing.expectEqual(@as(usize, 0), arr.len());
}

test "remove" {
    var arr = initForTests(usize, usize);
    defer arr.deinit(std.testing.allocator);

    try arr.assign(std.testing.allocator, 1, @as(usize, 100));
    try arr.assign(std.testing.allocator, 2, @as(usize, 200));

    arr.swapRemove(2);

    try std.testing.expectEqual(@as(usize, 100), arr.getAs(usize, 1).?.*);
    try std.testing.expectEqual(@as(usize, 1), arr.len());
}

test "reassign" {
    var arr = initForTests(usize, usize);
    defer arr.deinit(std.testing.allocator);

    try arr.assign(std.testing.allocator, 0, @as(usize, 10));
    try arr.assign(std.testing.allocator, 1, @as(usize, 20));

    try std.testing.expectEqual(@as(usize, 10), arr.getAs(usize, 0).?.*);
    try std.testing.expectEqual(@as(usize, 20), arr.getAs(usize, 1).?.*);

    arr.reassign(0, 2);

    try std.testing.expect(!arr.contains(0));
    try std.testing.expectEqual(@as(usize, 10), arr.getAs(usize, 2).?.*);
    try std.testing.expectEqual(@as(usize, 20), arr.getAs(usize, 1).?.*);
}

test "capacity" {
    var arr = initForTests(usize, usize);
    defer arr.deinit(std.testing.allocator);

    try arr.assign(std.testing.allocator, 0, @as(usize, 10));
    try arr.assign(std.testing.allocator, 1, @as(usize, 20));
}
