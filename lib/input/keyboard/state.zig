usingnamespace @import("root").preamble;

const kb = lib.input.keyboard;

pub const KeyboardState = struct {
    const pressedState = std.PackedIntArray(bool, @typeInfo(kb.keys.Location).Enum.fields.len);

    is_pressed: pressedState = std.mem.zeroInit(pressedState, .{}),
    layout: kb.layouts.KeyboardLayout = config.keyboard_layout,

    pub fn pressed(self: *const @This(), location: kb.keys.Location) bool {
        return self.is_pressed.get(@enumToInt(location));
    }

    pub fn isShiftPressed(self: *const @This()) bool {
        return self.pressed(.left_shift) or self.pressed(.right_shift);
    }

    pub fn isAltPressed(self: *const @This()) bool {
        return self.pressed(.left_alt) or self.pressed(.right_alt);
    }

    pub fn isSuperPressed(self: *const @This()) bool {
        return self.pressed(.left_super) or self.pressed(.right_super);
    }

    pub fn isCtrlPressed(self: *const @This()) bool {
        return self.pressed(.left_ctrl) or self.pressed(.right_ctrl);
    }

    pub fn event(self: *@This(), t: kb.event.EventType, location: kb.keys.Location) !void {
        const input = try kb.layouts.getInput(self, location, self.layout);
        switch (t) {
            .press => {
                self.is_pressed.set(@enumToInt(location), true);
            },
            .release => {
                self.is_pressed.set(@enumToInt(location), false);
            },
        }
        // TODO: Send `input` and `location` to listeners
        _ = location;
        _ = input;
    }
};
