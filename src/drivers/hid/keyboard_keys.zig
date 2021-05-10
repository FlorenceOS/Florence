/// Represents the physical location of a key on the keyboard, not affected by keyboard layouts
pub const Location = enum {
  Escape,
  F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,
  F13, F14, F15, F16, F17, F18, F19, F20, F21, F22, F23, F24,
  LeftOf1,
  // Number key row, 123...0
  NumberKey1, NumberKey2, NumberKey3, NumberKey4, NumberKey5, NumberKey6, NumberKey7, NumberKey8, NumberKey9, NumberKey0,
  RightOf0, LeftOfBackspace, Backspace,
  // Top line,    QWERTY: QWERTY...
  Tab,
  Line1_1, Line1_2, Line1_3, Line1_4, Line1_5, Line1_6, Line1_7, Line1_8, Line1_9, Line1_10, Line1_11, Line1_12, Line1_13,
  // Middle line, QWERTY: ASDFGH...
  CapsLock,
  Line2_1, Line2_2, Line2_3, Line2_4, Line2_5, Line2_6, Line2_7, Line2_8, Line2_9, Line2_10, Line2_11, Line2_12,
  Enter,
  // Bottom line, QWERTY: ZXCVBN...
  LeftShift, RightOfLeftShift,
  Line3_1, Line3_2, Line3_3, Line3_4, Line3_5, Line3_6, Line3_7, Line3_8, Line3_9, Line3_10,
  RightShift,

  // Control keys along the bottom
  LeftCtrl, RightCtrl,
  LeftSuper, RightSuper,
  LeftAlt, RightAlt,
  Spacebar,
  OptionKey, // Between right super and right control

  // Directional keys
  ArrowUp, ArrowLeft,  ArrowDown, ArrowRight,

  // Group above directional keys
  PrintScreen, PauseBreak, ScrollLock, Insert, Home,
  PageUp, Delete, End, PageDown,

  // Numpad
  NumLock, NumpadDivision, NumpadMultiplication,
  Numpad7, Numpad8, Numpad9, NumpadSubtraction,
  Numpad4, Numpad5, Numpad6, NumpadAddition,
  Numpad1, Numpad2, Numpad3,
  Numpad0, NumpadPoint, NumpadEnter,

  // Multimedia keys
  MediaStop, MediaRewind, MediaPausePlay, MediaForward, MediaMute,
  MediaVolumeUp, MediaVolumeDown,
};

/// Represent the intent of pressing the key, affected by keyboard layout
pub const Input = enum {
  // Traditional numbers
  @"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"0",

  // Traditional letters
  Q, W, E, R, T, Y, U, I, O, P,
   A, S, D, F, G, H, J, K, L,
     Z, X, C, V, B, N, M,

  // Control keys
  Spacebar, OptionKey, Backspace, Tab, Escape, CapsLock, Enter,

  F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,
  F13, F14, F15, F16, F17, F18, F19, F20, F21, F22, F23, F24,

  // Modifier keys
  LeftShift, RightShift,
  LeftCtrl, RightCtrl,
  LeftSuper, RightSuper,
  LeftAlt, RightAlt,

  // The buttons traditionally above the arrow keys
  PrintScreen, PauseBreak, ScrollLock, Insert, Home,
  PageUp, Delete, End, PageDown,

  // Arrow keys
  ArrowUp, ArrowLeft, ArrowDown, ArrowRight,

  // Punctuation
  ExclamationMark, QuotationMark, Hash, CurrencySign, Percent,
  Ampersand, Forwardslash, Backslash, Questionmark, At, DollarCurrency,
  Caret, Asterisk, Period, Comma, Colon, Semicolon, Plus, Minus,
  Underscore, Equals, VerticalBar, Tilde, Backtick, Apostrophe,
  PoundCurrency, Plusminus, Acute, Umlaut, EuroCurrency, YenCurrency,
  ParagraphSign, SectionSign,

  OpenSqBracket, CloseSqBracket,
  OpenCurlyBrace, CloseCurlyBrace,
  OpenParen, CloseParen,
  LessThan, GreaterThan,

  // Numpad
  NumLock, NumpadDivision, NumpadMultiplication,
  Numpad7, Numpad8, Numpad9, NumpadSubtraction,
  Numpad4, Numpad5, Numpad6, NumpadAddition,
  Numpad1, Numpad2, Numpad3,
  Numpad0, NumpadPoint, NumpadEnter,

  // Multimedia keys
  MediaStop, MediaRewind, MediaPausePlay, MediaForward, MediaMute,
  MediaVolumeUp, MediaVolumeDown,

  // International letters
  AWithUmlaut, OWithUmlaut, AWithRing, SlashedO, Ash,
};

const wasd_directional = .{
  .up = KeyLocation.Line1_2,
  .left = KeyLocation.Line2_1,
  .down = KeyLocation.Line2_2,
  .right = KeyLocation.Line2_3,
};

const arrow_directional = .{
  .up = KeyLocation.ArrowUp,
  .left = KeyLocation.ArrowLeft,
  .down = KeyLocation.ArrowDown,
  .right = KeyLocation.ArrowRight,
};

const numpad_directional = .{
  .up = KeyLocation.Numpad8,
  .left = KeyLocation.Numpad4,
  .down = KeyLocation.Numpad2,
  .right = KeyLocation.Numpad6,
};
