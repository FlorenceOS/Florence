#include "flo/Florence.hpp"
#include "flo/Paging.hpp"
#include "flo/CPU.hpp"
#include "flo/IO.hpp"

#include <algorithm>

using flo::Decimal;

using Constructor = void(*)();

extern "C" Constructor constructorsStart;
extern "C" Constructor constructorsEnd;

extern "C" void doConstructors() {
  std::for_each(&constructorsStart, &constructorsEnd, [](Constructor c){
    (*c)();
  });
}

extern "C" u64 unknownField;
extern "C" flo::PhysicalAddress physFreeHead;
extern "C" flo::VirtualAddress physBase;
extern "C" u64 physMemRanges;
extern "C" u64 displayWidth;
extern "C" u64 displayHeight;
extern "C" u64 displayPitch;
extern "C" u64 framebuffer;
extern "C" u64 driveNumber;

namespace {
  auto pline = flo::makePline("[FLORKLOAD] ");
}

namespace flo {
  void putchar(char c) {
    flo::IO::serial1.write(c);
  }

  void feedLine() {
    flo::IO::serial1.write('\n');
  }

  void setColor(flo::IO::Color col) {
    flo::IO::serial1.setColor(col);
  }

  u8 *getPtrPhys(flo::PhysicalAddress phys) {
    return (u8 *)(phys() + physBase());
  }

  void returnPhysicalPage(flo::PhysicalAddress phys, int pageLevel) {
    u64 sz;
    switch(pageLevel) {
      case 1:
        // Ah yes we know how to handle this, just push it onto the freelist
        *getPhys<PhysicalAddress>(phys) = std::exchange(physFreeHead, phys);
        return;
      case 2: sz = flo::Paging::PageSize<2>; break;
      case 3: sz = flo::Paging::PageSize<3>; break;
      case 4: sz = flo::Paging::PageSize<4>; break;
      case 5: sz = flo::Paging::PageSize<5>; break;
      default: pline("Unkown paging level: ", Decimal{pageLevel}); flo::CPU::hang();
    }

    pline("TODO: Handle return of physical page ", phys(), " of size ", sz, ", just splitting for now.");
    while(sz) {
      returnPhysicalPage(phys, 1);
      phys += PhysicalAddress{flo::Paging::PageSize<1>};
      sz -= flo::Paging::PageSize<1>;
    }
  }
}

extern "C" void assertAssumptions() {
  auto check =
    [](auto &value) {
      if(unknownField == (u64)value) {
        pline("Unset field!!", (u64)value);
        flo::CPU::hang();
      }
    };

  check(physFreeHead);
  check(physMemRanges);
  check(displayWidth);
  check(displayHeight);
  check(displayPitch);
  check(framebuffer);
  check(driveNumber);
}

extern "C" void unmapLowMemory() {
  constexpr auto lowMemoryLimit = flo::Util::mega(512ull);

  flo::printPaging(*flo::Paging::getPagingRoot(), pline);
  pline("Unmapping everything below ", lowMemoryLimit, "...");
  flo::Paging::unmap<false>(flo::VirtualAddress{0}, lowMemoryLimit);
  pline("Finished unmapping low memory!");
  flo::printPaging(*flo::Paging::getPagingRoot(), pline);
}

extern "C" void consumeHighPhysicalMemory() {
  pline("Woop, running at ", &consumeHighPhysicalMemory, "!");
  flo::CPU::hang();
}
