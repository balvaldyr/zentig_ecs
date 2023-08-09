const ztg = @import("../../init.zig");
const Time = ztg.base.Time;

const Lifetime = @This();

max: f32,
current: f32 = 0.0,
is_dead: bool = false,

tick_rate: TimeScale = .scaled_time,
on_death: OnDeath = .destroy,

pub const TimeScale = enum {
    scaled_time,
    real_time,
};

pub const OnDeath = union(enum) {
    destroy,
    callback: *const fn (*Lifetime, ztg.Entity) anyerror!void,
};

pub fn include(comptime wb: *ztg.WorldBuilder) void {
    wb.addComponents(&.{Lifetime});
    wb.addSystemsToStage(.update, .{ztg.after(.body, pou_lifetimes)});
}

fn pou_lifetimes(com: ztg.Commands, q: ztg.Query(.{ ztg.Entity, Lifetime }), time: Time) !void {
    for (q.items(0), q.items(1)) |ent, lt| {
        if (lt.is_dead) continue;

        lt.current += time.dt;
        if (lt.current >= lt.max) {
            lt.is_dead = true;

            switch (lt.on_death) {
                .destroy => try com.removeEnt(ent),
                .callback => |cb| try cb(lt, ent),
            }
        }
    }
}
