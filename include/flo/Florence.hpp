#pragma once

#include "Ints.hpp"

#include "flo/StrongTypedef.hpp"

namespace flo {
  struct VirtualAddress: flo::StrongTypedef<VirtualAddress, u64> {
    using flo::StrongTypedef<VirtualAddress, u64>::StrongTypedef;
  };

  struct PhysicalAddress: flo::StrongTypedef<PhysicalAddress, u64> {
    using flo::StrongTypedef<PhysicalAddress, u64>::StrongTypedef;
  };

  struct PhysicalMemoryRange {
    flo::PhysicalAddress begin;
    flo::PhysicalAddress end;
  };

  extern u8 *getPtrVirt(VirtualAddress);
  extern u8 *getPtrPhys(PhysicalAddress);

  template<typename T>
  T *getPhys(PhysicalAddress addr) { return reinterpret_cast<T *>(getPtrPhys(addr)); }
  template<typename T>
  T *getVirt(VirtualAddress addr)  { return reinterpret_cast<T *>(getPtrVirt(addr)); }

  template<typename T>
  struct Decimal { T val; };
  template<typename T>
  Decimal(T) -> Decimal<T>;

  struct Spaces { int numSpaces; };
  inline auto spaces(int numSpaces) { return Spaces{numSpaces}; }

  struct PhysicalFreeList {
    static PhysicalAddress getPhysicalPage(int pageLevel);
    static void returnPhysicalPage(PhysicalAddress, int pageLevel);
  private:
    flo::PhysicalAddress lvl1 = PhysicalAddress{0};
    flo::PhysicalAddress lvl2 = PhysicalAddress{0};
    flo::PhysicalAddress lvl3 = PhysicalAddress{0};
    flo::PhysicalAddress lvl4 = PhysicalAddress{0};
    flo::PhysicalAddress lvl5 = PhysicalAddress{0};
  };

  // This instance is always the one used by the static members. Only define others for copying contents.
  inline PhysicalFreeList physFree;

  namespace Impl {
    struct StackFrame {
      StackFrame *prev;
      uptr retaddr;
    };
  }

  // Invalidated on function return
  Impl::StackFrame *__attribute__((always_inline)) getStackFrame() {
    Impl::StackFrame *currentFrame;

    if constexpr(sizeof(uptr) == 8)
      asm("mov %%rbp, %0" : "=r"(currentFrame));

    if constexpr(sizeof(uptr) == 4)
      asm("mov %%ebp, %0" : "=r"(currentFrame));

    return currentFrame;
  }

  template<typename Output>
  void getStackTrace(Impl::StackFrame const *frame, Output &&out) {
    while(frame->retaddr || frame->prev) {
      out(*frame);
      frame = frame->prev;
    };
  }
}
