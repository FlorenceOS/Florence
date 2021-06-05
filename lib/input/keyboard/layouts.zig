usingnamespace @import("root").preamble;

const kb = lib.input.keyboard;

pub const KeyboardLayout = enum {
    en_US_QWERTY,
    sv_SE_QWERTY,
};

// Keys that are common between keyboard layouts
fn keyLookupDefault(key: kb.keys.Location) error{UnknownKey}!kb.keys.Input {
    return switch (key) {
        .escape => .escape,
        .leftShift => .leftShift,
        .rightShift => .rightShift,
        .leftCtrl => .leftCtrl,
        .rightCtrl => .rightCtrl,
        .leftSuper => .leftSuper,
        .rightSuper => .rightSuper,
        .leftAlt => .leftAlt,
        .rightAlt => .rightAlt,
        .spacebar => .spacebar,
        .optionKey => .optionKey,
        .printScreen => .printScreen,
        .pauseBreak => .pauseBreak,
        .scrollLock => .scrollLock,
        .insert => .insert,
        .home => .home,
        .pageUp => .pageUp,
        .delete => .delete,
        .end => .end,
        .pageDown => .pageDown,
        .arrowUp => .arrowUp,
        .arrowleft => .arrowleft,
        .arrowDown => .arrowDown,
        .arrowright => .arrowright,
        .backspace => .backspace,

        .mediaStop => .mediaStop,
        .mediaRewind => .mediaRewind,
        .mediaPausePlay => .mediaPausePlay,
        .mediaForward => .mediaForward,
        .mediaMute => .mediaMute,
        .mediaVolumeUp => .mediaVolumeUp,
        .mediaVolumeDown => .mediaVolumeDown,

        .tab => .tab,
        .capsLock => .capsLock,
        .enter => .enter,

        .numLock => .numLock,
        .numpadDivision => .numpadDivision,
        .numpadMultiplication => .numpadMultiplication,

        .numpad7 => .numpad7,
        .numpad8 => .numpad8,
        .numpad9 => .numpad9,
        .numpadSubtraction => .numpadSubtraction,

        .numpad4 => .numpad4,
        .numpad5 => .numpad5,
        .numpad6 => .numpad6,
        .numpadAddition => .numpadAddition,

        .numpad1 => .numpad1,
        .numpad2 => .numpad2,
        .numpad3 => .numpad3,

        .numpad0 => .numpad0,
        .numpadPoint => .numpadPoint,
        .numpadEnter => .numpadEnter,

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
        .leftOf1 => {
            if (alt) return kb.keys.Input.paragraphSign;
            return kb.keys.Input.sectionSign;
        },
        .numberKey1 => {
            if (shift) return kb.keys.Input.exclamationMark;
            return kb.keys.Input.@"1";
        },
        .numberKey2 => {
            if (alt) return kb.keys.Input.at;
            if (shift) return kb.keys.Input.quotationMark;
            return kb.keys.Input.@"2";
        },
        .numberKey3 => {
            if (alt) return kb.keys.Input.poundSign;
            if (shift) return kb.keys.Input.hash;
            return kb.keys.Input.@"3";
        },
        .numberKey4 => {
            if (alt) return kb.keys.Input.dollarSign;
            if (shift) return kb.keys.Input.currencySign;
            return kb.keys.Input.@"4";
        },
        .numberKey5 => {
            if (alt) return kb.keys.Input.euroSign;
            if (shift) return kb.keys.Input.percent;
            return kb.keys.Input.@"5";
        },
        .numberKey6 => {
            if (alt) return kb.keys.Input.yenCurrency;
            if (shift) return kb.keys.Input.ampersand;
            return kb.keys.Input.@"6";
        },
        .numberKey7 => {
            if (alt) return kb.keys.Input.openCurlyBrace;
            if (shift) return kb.keys.Input.forwardSlash;
            return kb.keys.Input.@"7";
        },
        .numberKey8 => {
            if (alt) return kb.keys.Input.openSqBracket;
            if (shift) return kb.keys.Input.openParen;
            return kb.keys.Input.@"8";
        },
        .numberKey9 => {
            if (alt) return kb.keys.Input.closeSqBracket;
            if (shift) return kb.keys.Input.closeParen;
            return kb.keys.Input.@"9";
        },
        .numberKey0 => {
            if (alt) return kb.keys.Input.closeCurlyBrace;
            if (shift) return kb.keys.Input.equals;
            return kb.keys.Input.@"0";
        },
        .rightOf0 => {
            if (alt) return kb.keys.Input.backSlash;
            if (shift) return kb.keys.Input.questionMark;
            return kb.keys.Input.plus;
        },
        .leftOfbackspace => {
            if (alt) return kb.keys.Input.plusminus;
            if (shift) return kb.keys.Input.backTick;
            return kb.keys.Input.acute;
        },

        .line1_11 => {
            if (alt) return kb.keys.Input.umlaut;
            return kb.keys.Input.aWithRing;
        },
        .line1_12 => {
            if (alt) return kb.keys.Input.tilde;
            if (shift) return kb.keys.Input.caret;
            return kb.keys.Input.umlaut;
        },

        .line2_10 => {
            if (alt) return kb.keys.Input.slashedO;
            return kb.keys.Input.oWithUmlaut;
        },
        .line2_11 => {
            if (alt) return kb.keys.Input.ash;
            return kb.keys.Input.aWithUmlaut;
        },
        .line2_12 => {
            if (alt) return kb.keys.Input.backTick;
            if (shift) return kb.keys.Input.asterisk;
            return kb.keys.Input.apostrophe;
        },

        .rightOfleftShift => {
            if (alt) return kb.keys.Input.verticalBar;
            if (shift) return kb.keys.Input.greaterThan;
            return kb.keys.Input.lessThan;
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
        .leftOf1 => {
            if (shift) return kb.keys.Input.tilde;
            return kb.keys.Input.backTick;
        },
        .numberKey1 => {
            if (shift) return kb.keys.Input.exclamationMark;
            return kb.keys.Input.@"1";
        },
        .numberKey2 => {
            if (shift) return kb.keys.Input.at;
            return kb.keys.Input.@"2";
        },
        .numberKey3 => {
            if (shift) return kb.keys.Input.hash;
            return kb.keys.Input.@"3";
        },
        .numberKey4 => {
            if (shift) return kb.keys.Input.dollarSign;
            return kb.keys.Input.@"4";
        },
        .numberKey5 => {
            if (shift) return kb.keys.Input.percent;
            return kb.keys.Input.@"5";
        },
        .numberKey6 => {
            if (shift) return kb.keys.Input.caret;
            return kb.keys.Input.@"6";
        },
        .numberKey7 => {
            if (shift) return kb.keys.Input.ampersand;
            return kb.keys.Input.@"7";
        },
        .numberKey8 => {
            if (shift) return kb.keys.Input.asterisk;
            return kb.keys.Input.@"8";
        },
        .numberKey9 => {
            if (shift) return kb.keys.Input.openParen;
            return kb.keys.Input.@"9";
        },
        .numberKey0 => {
            if (shift) return kb.keys.Input.closeParen;
            return kb.keys.Input.@"0";
        },
        .rightOf0 => {
            if (shift) return kb.keys.Input.underscore;
            return kb.keys.Input.minus;
        },

        .leftOfbackspace => {
            if (shift) return kb.keys.Input.plus;
            return kb.keys.Input.equals;
        },

        .line1_11 => {
            if (shift) return kb.keys.Input.openCurlyBrace;
            return kb.keys.Input.openSqBracket;
        },
        .line1_12 => {
            if (shift) return kb.keys.Input.closeCurlyBrace;
            return kb.keys.Input.closeSqBracket;
        },
        .line1_13 => {
            if (shift) return kb.keys.Input.verticalBar;
            return kb.keys.Input.backSlash;
        },

        .line2_10 => {
            if (shift) return kb.keys.Input.colon;
            return kb.keys.Input.semicolon;
        },
        .line2_11 => {
            if (shift) return kb.keys.Input.apostrophe;
            return kb.keys.Input.quotationMark;
        },

        .line3_8 => {
            if (shift) return kb.keys.Input.lessThan;
            return kb.keys.Input.comma;
        },
        .line3_9 => {
            if (shift) return kb.keys.Input.greaterThan;
            return kb.keys.Input.period;
        },
        .line3_10 => {
            if (shift) return kb.keys.Input.questionMark;
            return kb.keys.Input.forwardSlash;
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
