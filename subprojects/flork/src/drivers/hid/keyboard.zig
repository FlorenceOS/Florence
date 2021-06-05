const os = @import("root").os;
const config = @import("root").config;
const std = @import("std");

pub const layouts = @import("keyboard_layouts.zig");
pub const keys = @import("keyboard_keys.zig");

pub const EventType = enum {
    Press,
    Release,
};

const pressed_state = std.PackedIntArray(bool, @typeInfo(keys.Location).Enum.fields.len);

pub const KeyboardState = struct {
    is_pressed: pressed_state = std.mem.zeroInit(pressed_state, .{}),
    layout: layouts.KeyboardLayout = config.user.keyboard_layout,

    pub fn pressed(self: *const @This(), location: keys.Location) bool {
        return self.is_pressed.get(@enumToInt(location));
    }

    pub fn is_shift_pressed(self: *const @This()) bool {
        return self.pressed(.LeftShift) or self.pressed(.RightShift);
    }

    pub fn is_alt_pressed(self: *const @This()) bool {
        return self.pressed(.LeftAlt) or self.pressed(.RightAlt);
    }

    pub fn is_super_pressed(self: *const @This()) bool {
        return self.pressed(.LeftSuper) or self.pressed(.RightSuper);
    }

    pub fn is_ctrl_pressed(self: *const @This()) bool {
        return self.pressed(.LeftCtrl) or self.pressed(.RightCtrl);
    }

    pub fn event(self: *@This(), t: EventType, location: keys.Location) void {
        const input = layouts.get_input(self, location, self.layout) catch |err| {
            switch (err) {
                error.unknownKey => {
                    os.log("Keyboard layout {s} doesn't support key location {s}, and no default was found!\n", .{ @tagName(self.layout), @tagName(location) });
                    return;
                },
            }
        };
        switch (t) {
            .Press => {
                //os.log("Press event: {s}\n", .{@tagName(location)});
                //os.log("Input event: {s}\n", .{@tagName(input)});
                self.is_pressed.set(@enumToInt(location), true);
            },
            .Release => {
                //os.log("Release event: {s}\n", .{@tagName(location)});
                self.is_pressed.set(@enumToInt(location), false);
            },
        }
    }
};
