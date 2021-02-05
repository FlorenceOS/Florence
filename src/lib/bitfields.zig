const std = @import("std");

pub fn bit(comptime field_type: type, comptime shamt: usize) type {
    return bit_t(field_type, u1, shamt);
}

test "bit" {
    const S = extern union {
        low: bit(u32, 0),
        high: bit(u32, 1),
        val: u32,
    };

    std.testing.expect(@sizeOf(S) == 4);
    std.testing.expect(@bitSizeOf(S) == 32);

    var s: S = .{ .val = 1 };

    std.testing.expect(s.low.read() == 1);
    std.testing.expect(s.high.read() == 0);

    s.low.write(0);
    s.high.write(1);

    std.testing.expect(s.val == 2);
}

pub fn boolean(comptime field_type: type, comptime shamt: usize) type {
    return bit_t(field_type, bool, shamt);
}

test "boolean" {
    const S = extern union {
        low: boolean(u32, 0),
        high: boolean(u32, 1),
        val: u32,
    };

    std.testing.expect(@sizeOf(S) == 4);
    std.testing.expect(@bitSizeOf(S) == 32);

    var s: S = .{ .val = 2 };

    std.testing.expect(s.low.read() == false);
    std.testing.expect(s.high.read() == true);

    s.low.write(true);
    s.high.write(false);

    std.testing.expect(s.val == 1);
}

pub fn bitfield(comptime field_type: type, comptime shamt: usize, comptime num_bits: usize) type {
    if (shamt + num_bits > @bitSizeOf(field_type))
        @compileError("bitfield doesn't fit");

    const self_mask: field_type = ((1 << num_bits) - 1) << shamt;

    const val_t = std.meta.Int(.unsigned, num_bits);

    return struct {
        dummy: field_type,

        fn field(self: anytype) field_t(@This(), @TypeOf(self), field_type) {
            return @ptrCast(field_t(@This(), @TypeOf(self), field_type), self);
        }

        pub fn write(self: anytype, val: val_t) void {
            self.field().* &= ~self_mask;
            self.field().* |= @intCast(field_type, val) << shamt;
        }

        pub fn read(self: anytype) val_t {
            const val: field_type = self.field().*;
            return @intCast(val_t, (val & self_mask) >> shamt);
        }
    };
}

test "bitfield" {
    const S = extern union {
        low: bitfield(u32, 0, 16),
        high: bitfield(u32, 16, 16),
        val: u32,
    };

    std.testing.expect(@sizeOf(S) == 4);
    std.testing.expect(@bitSizeOf(S) == 32);

    var s: S = .{ .val = 0x13376969 };

    std.testing.expect(s.low.read() == 0x6969);
    std.testing.expect(s.high.read() == 0x1337);

    s.low.write(0x1337);
    s.high.write(0x6969);

    std.testing.expect(s.val == 0x69691337);
}

fn field_t(comptime self_t: type, comptime t: type, comptime val_t: type) type {
    return switch (t) {
        *self_t => *val_t,
        *const self_t => *const val_t,
        *volatile self_t => *volatile val_t,
        *const volatile self_t => *const volatile val_t,

        else => @compileError("wtf you doing"),
    };
}

fn bit_t(comptime field_type: type, comptime val_t: type, comptime shamt: usize) type {
    const self_bit: field_type = (1 << shamt);

    return struct {
        bits: bitfield(field_type, shamt, 1),

        pub fn set(self: anytype) void {
            self.bits.field().* |= self_bit;
        }

        pub fn unset(self: anytype) void {
            self.bits.field().* &= ~self_bit;
        }

        pub fn read(self: anytype) val_t {
            return @bitCast(val_t, @truncate(u1, self.bits.field().* >> shamt));
        }

        // Since these are mostly used with MMIO, I want to avoid
        // reading the memory just to write it again, also races
        pub fn write(self: anytype, val: val_t) void {
            if (@bitCast(bool, val)) {
                self.set();
            } else {
                self.unset();
            }
        }
    };
}
