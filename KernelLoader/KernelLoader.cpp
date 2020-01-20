#include "flo/Containers/StaticVector.hpp"
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
extern "C" flo::PhysicalAddress physFreeHead1;
extern "C" flo::PhysicalAddress physFreeHead2;
extern "C" flo::PhysicalAddress physFreeHead3;
extern "C" flo::PhysicalAddress physFreeHead4;
extern "C" flo::PhysicalAddress physFreeHead5;
extern "C" flo::VirtualAddress physBase;
extern "C" flo::StaticVector<flo::PhysicalMemoryRange, 0x10ull> *physMemRanges;
extern "C" u64 displayWidth;
extern "C" u64 displayHeight;
extern "C" u64 displayPitch;
extern "C" u64 framebuffer;
extern "C" u64 driveNumber;

namespace {
  auto pline = flo::makePline("[FLORKLOAD] ");
  constexpr bool quiet = false;
}

namespace flo {
  void putchar(char c) {
    if constexpr(!quiet)
      flo::IO::serial1.write(c);
  }

  void feedLine() {
    if constexpr(!quiet)
      flo::IO::serial1.write('\n');
  }

  void setColor(flo::IO::Color col) {
    if constexpr(!quiet)
      flo::IO::serial1.setColor(col);
  }

  u8 *getPtrPhys(flo::PhysicalAddress phys) {
    return (u8 *)(phys() + physBase());
  }

  void returnPhysicalPage(flo::PhysicalAddress phys, int pageLevel) {
    switch(pageLevel) {
      case 1: *getPhys<PhysicalAddress>(phys) = std::exchange(physFreeHead1, phys); return;
      case 2: *getPhys<PhysicalAddress>(phys) = std::exchange(physFreeHead2, phys); return;
      case 3: *getPhys<PhysicalAddress>(phys) = std::exchange(physFreeHead3, phys); return;
      case 4: *getPhys<PhysicalAddress>(phys) = std::exchange(physFreeHead4, phys); return;
      case 5: *getPhys<PhysicalAddress>(phys) = std::exchange(physFreeHead5, phys); return;
      default: pline("Unkown paging level: ", Decimal{pageLevel}); flo::CPU::hang();
    }
  }
}

extern "C" void assertAssumptions() {
  auto check =
    [](auto &value) {
      auto v = *(u64*)&value;
      if(unknownField == v) {
        pline("Unset field ", v, "!!");
        flo::CPU::hang();
      }
    };

  check(physFreeHead1);
  check(physFreeHead2);
  check(physFreeHead3);
  check(physFreeHead4);
  check(physFreeHead5);
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
