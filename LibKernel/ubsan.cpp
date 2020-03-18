#include "flo/Assert.hpp"
#include "flo/IO.hpp"

// Alignment must be a power of 2.
#define is_aligned(value, alignment) !(value & (alignment - 1))


struct source_location {
  const char *file;
  u32 line;
  u32 column;
};

static_assert(sizeof(source_location) == sizeof(void *) + 8);

struct type_descriptor {
  u16 kind;
  u16 info;
  char name[];
};

static_assert(sizeof(type_descriptor) == 4);

struct type_mismatch_info {
  source_location location;
  type_descriptor const *type;
  uptr alignment;
  u8 type_check_kind;
};

static_assert(sizeof(type_mismatch_info) == sizeof(source_location) + sizeof(void *) * 3);

struct type_mismatch_info_v1 {
  source_location location;
  type_descriptor const *type;
  u8 log_alignment;
  u8 type_check_kind;
};

const char *type_check_kinds[] = {
  "Load of",
  "Store to",
  "Reference binding to",
  "Member access within",
  "Member call on",
  "Constructor call on",
  "Downcast of",
  "Downcast of",
  "Upcast of",
  "Cast to virtual base of",
  "_Nonnull binding to",
  "Dynamic operation on",
};

namespace flo::ubsan {
  namespace {
    auto pline = flo::makePline<false>("[UBSAN]");

    void log_location(source_location const &loc) {
      flo::ubsan::pline("Undefined behaviour at ", loc.file, ":", flo::Decimal{loc.line}, ":", flo::Decimal{loc.column}, "!");
    }
  }
}

extern "C"
void __ubsan_handle_type_mismatch(type_mismatch_info const *type_mismatch, uptr ptr) {
  flo::ubsan::log_location(type_mismatch->location);
  if(!ptr) {
    flo::ubsan::pline("Null pointer access");
  } else if(type_mismatch->alignment && (ptr & (type_mismatch->alignment - 1))) {
    flo::ubsan::pline("Misaligned memory read, pointer used was ", ptr, " and required alignment for ", type_mismatch->type->name, " is ", type_mismatch->alignment);
  } else {
    flo::ubsan::pline("Insufficient size");
    if(type_mismatch->type_check_kind < flo::Util::arrSz(type_check_kinds))
      flo::ubsan::pline(type_check_kinds[type_mismatch->type_check_kind], " address ", ptr, " with insufficient space for object of type ", type_mismatch->type->name);
    else
      flo::ubsan::pline("Unhandled kind ", flo::Decimal{type_mismatch->type_check_kind}, " at address ", ptr, " with insufficient space for object of type ", type_mismatch->type->name);
  }
  assert_not_reached();
}

extern "C"
void __ubsan_handle_type_mismatch_v1(type_mismatch_info_v1 const *type_mismatch, uptr ptr) {
  flo::ubsan::log_location(type_mismatch->location);
  if(!ptr) {
    flo::ubsan::pline("Null pointer access");
  } else if(ptr & (1 << ((type_mismatch->log_alignment) - 1))) {
    flo::ubsan::pline("Misaligned memory read, pointer used was ", ptr, " and required alignment for ", type_mismatch->type->name, " is ", type_mismatch->log_alignment, " bits");
  } else {
    flo::ubsan::pline("Insufficient size");
    if(type_mismatch->type_check_kind < flo::Util::arrSz(type_check_kinds))
      flo::ubsan::pline(type_check_kinds[type_mismatch->type_check_kind], " address ", ptr, " with insufficient space for object of type ", type_mismatch->type->name);
    else
      flo::ubsan::pline("Unhandled kind ", flo::Decimal{type_mismatch->type_check_kind}, " at address ", ptr, " with insufficient space for object of type ", type_mismatch->type->name);
  }
  assert_not_reached();
}

extern "C"
void __ubsan_handle_pointer_overflow() {
  flo::ubsan::pline("Pointer overflow!");
  assert_not_reached();
}

extern "C"
void __ubsan_handle_builtin_unreachable() {
  flo::ubsan::pline("__builtin_unreachable() hit!");
  assert_not_reached();
}

extern "C"
void __ubsan_handle_add_overflow() {
  flo::ubsan::pline("Add overflow!");
  assert_not_reached();
}

extern "C"
void __ubsan_handle_shift_out_of_bounds() {
  flo::ubsan::pline("Shift out of bounds!");
  assert_not_reached();
}

extern "C"
void __ubsan_handle_load_invalid_value() {
  flo::ubsan::pline("Load invalid value!");
  assert_not_reached();
}

extern "C"
void __ubsan_handle_out_of_bounds() {
  flo::ubsan::pline("Out of bounds!");
  assert_not_reached();
}

extern "C"
void __ubsan_handle_function_type_mismatch_v1() {
  flo::ubsan::pline("Function type mismatch!");
  assert_not_reached();
}

extern "C"
void __ubsan_handle_sub_overflow() {
  flo::ubsan::pline("Sub overflow!");
  assert_not_reached();
}

extern "C"
void __ubsan_handle_mul_overflow() {
  flo::ubsan::pline("Mul overflow!");
  assert_not_reached();
}

extern "C"
void __ubsan_handle_divrem_overflow() {
  flo::ubsan::pline("Divrem overflow!");
  assert_not_reached();
}

namespace __cxxabiv1 {
  class __function_type_info {
    virtual ~__function_type_info();
  };

  __function_type_info::~__function_type_info() {
    assert_not_reached();
  }
}
