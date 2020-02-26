#include "Ints.hpp"

#include "flo/Assert.hpp"
#include "flo/CPU.hpp"
#include "flo/Florence.hpp"
#include "flo/IO.hpp"
#include "flo/Kernel.hpp"
#include "flo/Paging.hpp"
#include "flo/Random.hpp"

namespace LibKernel {
  namespace {
    constexpr bool quiet = false;
    auto pline = flo::makePline<quiet>("[LibKernel]");

    struct {
      u64 a = 0x69FF1337ABCDEFAAULL;
      u64 b = 0x420B16D1CCABC123ULL;
    } simpleRandState;

    u64 simpleRand() {
      auto t = simpleRandState.a;
      auto const s = simpleRandState.b;
      simpleRandState.a = s;
      t ^= t << 23;
      t ^= t >> 17;
      t ^= s ^ (s >> 26);
      simpleRandState.b = t;
      return t + s;
    }

    u64 rdrand() {
      if constexpr(sizeof(uptr) == 4) {
        u32 val1, val2;
        asm volatile("1:rdrand %0\njnc 1b\n":"=r"(val1));
        asm volatile("1:rdrand %0\njnc 1b\n":"=r"(val2));
        return (u64)val1 | (u64)val2 << 32;
      }
      else if constexpr(sizeof(uptr) == 8) {
        u64 retval;
        asm volatile("1:rdrand %0\njnc 1b\n":"=r"(retval));
        return retval;
      }
    }
  }
}

extern "C" int memcmp(const void *lhs, const void *rhs, uSz num) {
  auto ul = reinterpret_cast<u8 const *>(lhs);
  auto ur = reinterpret_cast<u8 const *>(rhs);

  while(num--) {
    int a = *ul++ - *ur++;
    if(a)
      return a;
  }
  return 0;
}

u64 flo::getRand() {
  if(flo::cpuid.rdrand)
    return LibKernel::rdrand();
  else
    return LibKernel::simpleRand();
}

extern "C" void atexit() { }

flo::PhysicalAddress flo::PhysicalFreeList::getPhysicalPage(int pageLevel) {
  auto tryGet =
    [pageLevel](flo::PhysicalAddress &currHead) {
      // Fast path, try to get from current level
      if(currHead())
        return flo::exchange(currHead, *getPhys<PhysicalAddress>(currHead));

      if(pageLevel == 5)
        return PhysicalAddress{0};

      // Slow path, try to get from next level
      auto next = physFree.getPhysicalPage(pageLevel + 1);

      if(!next) {
        if(pageLevel == 1) {
          LibKernel::pline("Ran out of physical pages on level ", pageLevel);
          flo::CPU::hang();
        }

        if(!next)
          return PhysicalAddress{0};
      }

      // Woop we got one, let's split it.
      auto stepSize = flo::Paging::pageSizes[pageLevel - 1]; // 0 indexed, we are 1 indexed

      // Return all pages but one
      for(int i = 0; i < flo::Paging::PageTableSize - 1; ++i) {
        physFree.returnPhysicalPage(next, pageLevel);
        next += PhysicalAddress{stepSize};
      }

      return next;
    };

  switch(pageLevel) {
  case 1: return tryGet(physFree.lvl1);
  case 2: return tryGet(physFree.lvl2);
  case 3: return tryGet(physFree.lvl3);
  case 4: return tryGet(physFree.lvl4);
  case 5: return tryGet(physFree.lvl5);
  default: LibKernel::pline("Unknown paging level: ", pageLevel); flo::CPU::hang();
  }

  __builtin_unreachable();
}

void flo::PhysicalFreeList::returnPhysicalPage(flo::PhysicalAddress phys, int pageLevel) {
  switch(pageLevel) {
  case 1: *getPhys<PhysicalAddress>(phys) = exchange(physFree.lvl1, phys); return;
  case 2: *getPhys<PhysicalAddress>(phys) = exchange(physFree.lvl2, phys); return;
  case 3: *getPhys<PhysicalAddress>(phys) = exchange(physFree.lvl3, phys); return;
  case 4: *getPhys<PhysicalAddress>(phys) = exchange(physFree.lvl4, phys); return;
  case 5: *getPhys<PhysicalAddress>(phys) = exchange(physFree.lvl5, phys); return;
  default: LibKernel::pline("Unkown paging level: ", Decimal{pageLevel}); flo::CPU::hang();
  }
}

void flo::assertionFailure(char const *file, u64 line, char const *error) {
  LibKernel::pline("Assertion failure at: ", file, ":", flo::Decimal{line}, ": ", error);

  flo::printBacktrace();

  flo::CPU::halt();
}


