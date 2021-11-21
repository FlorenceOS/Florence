const kb = @import("keyboard.zig");

pub const KeyboardLayout = enum {
    en_US_QWERTY,
    sv_SE_QWERTY,
};

// Keys that are common between keyboard layouts
fn keyLookupDefault(key: kb.keys.Location) error{UnknownKey}!kb.keys.Input {
    return switch (key) {
        .escape => .escape,
        .left_shift => .left_shift,
        .right_shift => .right_shift,
        .left_ctrl => .left_ctrl,
        .right_ctrl => .right_ctrl,
        .left_super => .left_super,
        .right_super => .right_super,
        .left_alt => .left_alt,
        .right_alt => .right_alt,
        .spacebar => .spacebar,
        .option_key => .option_key,
        .print_screen => .print_screen,
        .pause_break => .pause_break,
        .scroll_lock => .scroll_lock,
        .insert => .insert,
        .home => .home,
        .page_up => .page_up,
        .delete => .delete,
        .end => .end,
        .page_down => .page_down,
        .arrow_up => .arrow_up,
        .arrow_left => .arrow_left,
        .arrow_down => .arrow_down,
        .arrow_right => .arrow_right,
        .backspace => .backspace,

        .media_stop => .media_stop,
        .media_rewind => .media_rewind,
        .media_pause_play => .media_pause_play,
        .media_forward => .media_forward,
        .media_mute => .media_mute,
        .media_volume_up => .media_volume_up,
        .media_volume_down => .media_volume_down,

        .tab => .tab,
        .capslock => .capslock,
        .enter => .enter,

        .numlock => .numlock,
        .numpad_div => .numpad_div,
        .numpad_mul => .numpad_mul,

        .numpad7 => .numpad7,
        .numpad8 => .numpad8,
        .numpad9 => .numpad9,
        .numpad_sub => .numpad_sub,

        .numpad4 => .numpad4,
        .numpad5 => .numpad5,
        .numpad6 => .numpad6,
        .numpad_add => .numpad_add,

        .numpad1 => .numpad1,
        .numpad2 => .numpad2,
        .numpad3 => .numpad3,

        .numpad0 => .numpad0,
        .numpad_point => .numpad_point,
        .numpad_enter => .numpad_enter,

        .f1 => .f1,
        .f2 => .f2,
        .f3 => .f3,
        .f4 => .f4,
        .f5 => .f5,
        .f6 => .f6,
        .f7 => .f7,
        .f8 => .f8,
        .f9 => .f9,
        .f10 => .f10,
        .f11 => .f11,
        .f12 => .f12,
        .f13 => .f13,
        .f14 => .f14,
        .f15 => .f15,
        .f16 => .f16,
        .f17 => .f17,
        .f18 => .f18,
        .f19 => .f19,
        .f20 => .f20,
        .f21 => .f21,
        .f22 => .f22,
        .f23 => .f23,
        .f24 => .f24,
        else => error.UnknownKey,
    };
}

fn queryQwertyFamily(key: kb.keys.Location) error{UnknownKey}!kb.keys.Input {
    return switch (key) {
        .line1_1 => .q,
        .line1_2 => .w,
        .line1_3 => .e,
        .line1_4 => .r,
        .line1_5 => .t,
        .line1_6 => .y,
        .line1_7 => .u,
        .line1_8 => .i,
        .line1_9 => .o,
        .line1_10 => .p,
        .line2_1 => .a,
        .line2_2 => .s,
        .line2_3 => .d,
        .line2_4 => .f,
        .line2_5 => .g,
        .line2_6 => .h,
        .line2_7 => .j,
        .line2_8 => .k,
        .line2_9 => .l,
        .line3_1 => .z,
        .line3_2 => .x,
        .line3_3 => .c,
        .line3_4 => .v,
        .line3_5 => .b,
        .line3_6 => .n,
        .line3_7 => .m,
        else => keyLookupDefault(key),
    };
}

fn sv_SE_QWERTY(state: *const kb.state.KeyboardState, key: kb.keys.Location) !kb.keys.Input {
    const shift = state.isShiftPressed();
    const alt = state.isAltPressed();

    switch (key) {
        .left_of1 => {
            if (alt) return kb.keys.Input.paragraph_sign;
            return kb.keys.Input.section_sign;
        },
        .number_key1 => {
            if (shift) return kb.keys.Input.exclamation_mark;
            return kb.keys.Input.@"1";
        },
        .number_key2 => {
            if (alt) return kb.keys.Input.at;
            if (shift) return kb.keys.Input.quotation_mark;
            return kb.keys.Input.@"2";
        },
        .number_key3 => {
            if (alt) return kb.keys.Input.pound_sign;
            if (shift) return kb.keys.Input.hash;
            return kb.keys.Input.@"3";
        },
        .number_key4 => {
            if (alt) return kb.keys.Input.dollar_sign;
            if (shift) return kb.keys.Input.currency_sign;
            return kb.keys.Input.@"4";
        },
        .number_key5 => {
            if (alt) return kb.keys.Input.euro_sign;
            if (shift) return kb.keys.Input.percent;
            return kb.keys.Input.@"5";
        },
        .number_key6 => {
            if (alt) return kb.keys.Input.yen_sign;
            if (shift) return kb.keys.Input.ampersand;
            return kb.keys.Input.@"6";
        },
        .number_key7 => {
            if (alt) return kb.keys.Input.open_curly_brace;
            if (shift) return kb.keys.Input.forward_slash;
            return kb.keys.Input.@"7";
        },
        .number_key8 => {
            if (alt) return kb.keys.Input.open_sq_bracket;
            if (shift) return kb.keys.Input.open_paren;
            return kb.keys.Input.@"8";
        },
        .number_key9 => {
            if (alt) return kb.keys.Input.close_sq_bracket;
            if (shift) return kb.keys.Input.close_paren;
            return kb.keys.Input.@"9";
        },
        .number_key0 => {
            if (alt) return kb.keys.Input.close_curly_brace;
            if (shift) return kb.keys.Input.equals;
            return kb.keys.Input.@"0";
        },
        .right_of0 => {
            if (alt) return kb.keys.Input.back_slash;
            if (shift) return kb.keys.Input.question_mark;
            return kb.keys.Input.plus;
        },
        .left_of_backspace => {
            if (alt) return kb.keys.Input.plusminus;
            if (shift) return kb.keys.Input.back_tick;
            return kb.keys.Input.acute;
        },

        .line1_11 => {
            if (alt) return kb.keys.Input.umlaut;
            return kb.keys.Input.a_with_ring;
        },
        .line1_12 => {
            if (alt) return kb.keys.Input.tilde;
            if (shift) return kb.keys.Input.caret;
            return kb.keys.Input.umlaut;
        },

        .line2_10 => {
            if (alt) return kb.keys.Input.slashedO;
            return kb.keys.Input.o_with_umlaut;
        },
        .line2_11 => {
            if (alt) return kb.keys.Input.ash;
            return kb.keys.Input.a_with_umlaut;
        },
        .line2_12 => {
            if (alt) return kb.keys.Input.back_tick;
            if (shift) return kb.keys.Input.asterisk;
            return kb.keys.Input.apostrophe;
        },

        .right_of_left_shift => {
            if (alt) return kb.keys.Input.vertical_bar;
            if (shift) return kb.keys.Input.greater_than;
            return kb.keys.Input.less_than;
        },
        .line3_8 => {
            if (shift) return kb.keys.Input.semicolon;
            return kb.keys.Input.comma;
        },
        .line3_9 => {
            if (shift) return kb.keys.Input.colon;
            return kb.keys.Input.period;
        },
        .line3_10 => {
            if (shift) return kb.keys.Input.underscore;
            return kb.keys.Input.minus;
        },

        else => return queryQwertyFamily(key),
    }
}

fn en_US_QWERTY(state: *const kb.state.KeyboardState, key: kb.keys.Location) !kb.keys.Input {
    const shift = state.isShiftPressed();

    switch (key) {
        .left_of1 => {
            if (shift) return kb.keys.Input.tilde;
            return kb.keys.Input.back_tick;
        },
        .number_key1 => {
            if (shift) return kb.keys.Input.exclamation_mark;
            return kb.keys.Input.@"1";
        },
        .number_key2 => {
            if (shift) return kb.keys.Input.at;
            return kb.keys.Input.@"2";
        },
        .number_key3 => {
            if (shift) return kb.keys.Input.hash;
            return kb.keys.Input.@"3";
        },
        .number_key4 => {
            if (shift) return kb.keys.Input.dollar_sign;
            return kb.keys.Input.@"4";
        },
        .number_key5 => {
            if (shift) return kb.keys.Input.percent;
            return kb.keys.Input.@"5";
        },
        .number_key6 => {
            if (shift) return kb.keys.Input.caret;
            return kb.keys.Input.@"6";
        },
        .number_key7 => {
            if (shift) return kb.keys.Input.ampersand;
            return kb.keys.Input.@"7";
        },
        .number_key8 => {
            if (shift) return kb.keys.Input.asterisk;
            return kb.keys.Input.@"8";
        },
        .number_key9 => {
            if (shift) return kb.keys.Input.open_paren;
            return kb.keys.Input.@"9";
        },
        .number_key0 => {
            if (shift) return kb.keys.Input.close_paren;
            return kb.keys.Input.@"0";
        },
        .right_of0 => {
            if (shift) return kb.keys.Input.underscore;
            return kb.keys.Input.minus;
        },

        .left_of_backspace => {
            if (shift) return kb.keys.Input.plus;
            return kb.keys.Input.equals;
        },

        .line1_11 => {
            if (shift) return kb.keys.Input.open_curly_brace;
            return kb.keys.Input.open_sq_bracket;
        },
        .line1_12 => {
            if (shift) return kb.keys.Input.close_curly_brace;
            return kb.keys.Input.close_sq_bracket;
        },
        .line1_13 => {
            if (shift) return kb.keys.Input.vertical_bar;
            return kb.keys.Input.back_slash;
        },

        .line2_10 => {
            if (shift) return kb.keys.Input.colon;
            return kb.keys.Input.semicolon;
        },
        .line2_11 => {
            if (shift) return kb.keys.Input.apostrophe;
            return kb.keys.Input.quotation_mark;
        },

        .line3_8 => {
            if (shift) return kb.keys.Input.less_than;
            return kb.keys.Input.comma;
        },
        .line3_9 => {
            if (shift) return kb.keys.Input.greater_than;
            return kb.keys.Input.period;
        },
        .line3_10 => {
            if (shift) return kb.keys.Input.question_mark;
            return kb.keys.Input.forward_slash;
        },

        else => return queryQwertyFamily(key),
    }
}

pub fn getInput(
    state: *const kb.state.KeyboardState,
    key: kb.keys.Location,
    layout: KeyboardLayout,
) !kb.keys.Input {
    return switch (layout) {
        .en_US_QWERTY => return en_US_QWERTY(state, key),
        .sv_SE_QWERTY => return sv_SE_QWERTY(state, key),
    };
}
