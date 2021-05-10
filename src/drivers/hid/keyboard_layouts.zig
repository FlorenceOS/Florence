const keyboard = @import("keyboard.zig");
const keys = @import("keyboard_keys.zig");

const Location = keys.Location;
const Input = keys.Input;

pub const KeyboardLayout = enum {
  en_US_QWERTY,
  sv_SE_QWERTY,
};

// Keys that are common between keyboard layouts
fn default_key_lookup(key: Location) error{unknownKey}!Input {
  return switch(key) {
    .Escape => .Escape,
    .LeftShift => .LeftShift, .RightShift => .RightShift,
    .LeftCtrl => .LeftCtrl, .RightCtrl => .RightCtrl,
    .LeftSuper => .LeftSuper, .RightSuper => .RightSuper,
    .LeftAlt => .LeftAlt, .RightAlt => .RightAlt,
    .Spacebar => .Spacebar,
    .OptionKey => .OptionKey,
    .PrintScreen => .PrintScreen,
    .PauseBreak => .PauseBreak,
    .ScrollLock => .ScrollLock,
    .Insert => .Insert,
    .Home => .Home,
    .PageUp => .PageUp,
    .Delete => .Delete,
    .End => .End,
    .PageDown => .PageDown,
    .ArrowUp => .ArrowUp,
    .ArrowLeft => .ArrowLeft,
    .ArrowDown => .ArrowDown,
    .ArrowRight => .ArrowRight,
    .Backspace => .Backspace,

    .MediaStop => .MediaStop,
    .MediaRewind => .MediaRewind,
    .MediaPausePlay => .MediaPausePlay,
    .MediaForward => .MediaForward, 
    .MediaMute => .MediaMute,
    .MediaVolumeUp => .MediaVolumeUp,
    .MediaVolumeDown => .MediaVolumeDown,

    .Tab => .Tab,
    .CapsLock => .CapsLock,

    .NumLock => .NumLock,
    .NumpadDivision => .NumpadDivision,
    .NumpadMultiplication => .NumpadMultiplication,

    .Numpad7 => .Numpad7,
    .Numpad8 => .Numpad8,
    .Numpad9 => .Numpad9,
    .NumpadSubtraction => .NumpadSubtraction,

    .Numpad4 => .Numpad4,
    .Numpad5 => .Numpad5,
    .Numpad6 => .Numpad6,
    .NumpadAddition => .NumpadAddition,

    .Numpad1 => .Numpad1,
    .Numpad2 => .Numpad2,
    .Numpad3 => .Numpad3,
    .Numpad0 => .Numpad0,
    .NumpadPoint => .NumpadPoint,

    .NumpadEnter => .NumpadEnter,


    .F1 => .F1, .F2 => .F2, .F3 => .F3, .F4 => .F4, .F5 => .F5, .F6 => .F6,
    .F7 => .F7, .F8 => .F8, .F9 => .F9, .F10 => .F10, .F11 => .F11, .F12 => .F12,
    .F13 => .F13, .F14 => .F14, .F15 => .F15, .F16 => .F16, .F17 => .F17, .F18 => .F18,
    .F19 => .F19, .F20 => .F20, .F21 => .F21, .F22 => .F22, .F23 => .F23, .F24 => .F24,
    else => error.unknownKey,
  };
}

fn qwerty_family(key: Location) error{unknownKey}!Input {
  return switch(key) {
    .Line1_1  => .Q,
    .Line1_2  => .W,
    .Line1_3  => .E,
    .Line1_4  => .R,
    .Line1_5  => .T,
    .Line1_6  => .Y,
    .Line1_7  => .U,
    .Line1_8  => .I,
    .Line1_9  => .O,
    .Line1_10 => .P,
    .Line2_1  => .A,
    .Line2_2  => .S,
    .Line2_3  => .D,
    .Line2_4  => .F,
    .Line2_5  => .G,
    .Line2_6  => .H,
    .Line2_7  => .J,
    .Line2_8  => .K,
    .Line2_9  => .L,
    .Line3_1  => .Z,
    .Line3_2  => .X,
    .Line3_3  => .C,
    .Line3_4  => .V,
    .Line3_5  => .B,
    .Line3_6  => .N,
    .Line3_7  => .M,
    else => default_key_lookup(key),
  };
}

fn sv_SE_QWERTY(state: *const keyboard.KeyboardState, key: Location) !Input {
  const shift = state.is_shift_pressed();
  const alt   = state.is_alt_pressed();

  switch(key) {
    .LeftOf1    => { if(alt)   return Input.ParagraphSign;   return Input.SectionSign; },
    .NumberKey1 => { if(shift) return Input.ExclamationMark; return Input.@"1"; },
    .NumberKey2 => {
      if(alt)   return Input.At;
      if(shift) return Input.QuotationMark;
                return Input.@"2";
    },
    .NumberKey3 => {
      if(alt)   return Input.PoundCurrency;
      if(shift) return Input.Hash;
                return Input.@"3";
    },
    .NumberKey4 => {
      if(alt)   return Input.DollarCurrency;
      if(shift) return Input.CurrencySign;
                return Input.@"4";
    },
    .NumberKey5 => {
      if(alt)   return Input.EuroCurrency;
      if(shift) return Input.Percent;
                return Input.@"5";
    },
    .NumberKey6 => {
      if(alt)   return Input.YenCurrency;
      if(shift) return Input.Ampersand;
                return Input.@"6";
    },
    .NumberKey7 => {
      if(alt)   return Input.OpenCurlyBrace;
      if(shift) return Input.Forwardslash;
                return Input.@"7";
    },
    .NumberKey8 => {
      if(alt)   return Input.OpenSqBracket;
      if(shift) return Input.OpenParen;
                return Input.@"8";
    },
    .NumberKey9 => {
      if(alt)   return Input.CloseSqBracket;
      if(shift) return Input.CloseParen;
                return Input.@"9";
    },
    .NumberKey0 => {
      if(alt)   return Input.CloseCurlyBrace;
      if(shift) return Input.Equals;
                return Input.@"0";
    },
    .RightOf0   => {
      if(alt)   return Input.Backslash;
      if(shift) return Input.Questionmark;
                return Input.Plus;
    },
    .LeftOfBackspace => {
      if(alt)   return Input.Plusminus;
      if(shift) return Input.Backtick;
                return Input.Acute;
    },

    .Line1_11 => { if(alt) return Input.Umlaut; return Input.AWithRing; },
    .Line1_12 => {
      if(alt)   return Input.Tilde;
      if(shift) return Input.Caret;
                return Input.Umlaut;
    },

    .Line2_10 => { if(alt) return Input.SlashedO; return Input.OWithUmlaut; },
    .Line2_11 => { if(alt) return Input.Ash;      return Input.AWithUmlaut; },
    .Line2_12 => {
      if(alt)   return Input.Backtick;
      if(shift) return Input.Asterisk;
                return Input.Apostrophe;
    },

    .RightOfLeftShift => {
      if(alt)   return Input.VerticalBar;
      if(shift) return Input.GreaterThan;
                return Input.LessThan;
    },
    .Line3_8  => { if(shift) return Input.Semicolon;  return Input.Comma; },
    .Line3_9  => { if(shift) return Input.Colon;      return Input.Period; },
    .Line3_10 => { if(shift) return Input.Underscore; return Input.Minus; },

    else => return qwerty_family(key),
  }
}

fn en_US_QWERTY(state: *const keyboard.KeyboardState, key: Location) !Input {
  const shift = state.is_shift_pressed();

  switch(key) {
    .NumberKey1 => { if(shift) return Input.ExclamationMark; return Input.@"1"; },
    .NumberKey2 => { if(shift) return Input.At;              return Input.@"2"; },
    .NumberKey3 => { if(shift) return Input.Hash;            return Input.@"3"; },
    .NumberKey4 => { if(shift) return Input.DollarCurrency;  return Input.@"4"; },
    .NumberKey5 => { if(shift) return Input.Percent;         return Input.@"5"; },
    .NumberKey6 => { if(shift) return Input.Caret;           return Input.@"6"; },
    .NumberKey7 => { if(shift) return Input.Ampersand;       return Input.@"7"; },
    .NumberKey8 => { if(shift) return Input.Asterisk;        return Input.@"8"; },
    .NumberKey9 => { if(shift) return Input.OpenParen;       return Input.@"9"; },
    .NumberKey0 => { if(shift) return Input.CloseParen;      return Input.@"0"; },
    .RightOf0   => { if(shift) return Input.Underscore;      return Input.Minus; },

    .LeftOfBackspace => { if(shift) return Input.Plus; return Input.Equals; },

    .Line1_11 => { if(shift) return Input.OpenCurlyBrace;  return Input.OpenSqBracket; },
    .Line1_12 => { if(shift) return Input.CloseCurlyBrace; return Input.CloseSqBracket; },
    .Line1_13 => { if(shift) return Input.VerticalBar;     return Input.Backslash; },

    .Line2_10 => { if(shift) return Input.Colon;      return Input.Semicolon; },
    .Line2_11 => { if(shift) return Input.Apostrophe; return Input.QuotationMark; },

    .Line3_8  => { if(shift) return Input.LessThan;     return Input.Comma; },
    .Line3_9  => { if(shift) return Input.GreaterThan;  return Input.Period; },
    .Line3_10 => { if(shift) return Input.Questionmark; return Input.Forwardslash; },


    else => return qwerty_family(key),
  }
}

pub fn get_input(state: *const keyboard.KeyboardState, key: Location, layout: KeyboardLayout) !Input {
  return switch(layout) {
    .en_US_QWERTY => return en_US_QWERTY(state, key),
    .sv_SE_QWERTY => return sv_SE_QWERTY(state, key),
  };
}
