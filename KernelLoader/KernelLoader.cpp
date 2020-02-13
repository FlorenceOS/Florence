#include "flo/Containers/StaticVector.hpp"
#include "flo/Algorithm.hpp"
#include "flo/Florence.hpp"
#include "flo/Kernel.hpp"
#include "flo/Paging.hpp"
#include "flo/CPU.hpp"
#include "flo/ELF.hpp"
#include "flo/IO.hpp"

using flo::Decimal;

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
extern "C" u8 bundledKernel[];
extern "C" u8 bundledKernelEnd[];

namespace {
  constexpr bool quiet = true;
  auto pline = flo::makePline<quiet>("[FLORKLOAD] ");

  flo::ELF64Image kernelELF{bundledKernel, bundledKernelEnd - bundledKernel};
}

extern "C" {
  u64 kernelEntry;

  flo::KernelArguments kernelArguments {
    &kernelELF
  };
}

void flo::putchar(char c) {
  if constexpr(!quiet)
    flo::IO::serial1.write(c);
}

void flo::feedLine() {
  if constexpr(!quiet)
    flo::IO::serial1.write('\n');
}

void flo::setColor(flo::IO::Color col) {
  if constexpr(!quiet)
    flo::IO::serial1.setColor(col);
}

u8 *flo::getPtrPhys(flo::PhysicalAddress phys) {
  return (u8 *)(phys() + physBase());
}

u8 *flo::getPtrVirt(flo::VirtualAddress virt) {
  return (u8 *)virt();
}

void flo::returnPhysicalPage(flo::PhysicalAddress phys, int pageLevel) {
  switch(pageLevel) {
    case 1: *getPhys<PhysicalAddress>(phys) = flo::exchange(physFreeHead1, phys); return;
    case 2: *getPhys<PhysicalAddress>(phys) = flo::exchange(physFreeHead2, phys); return;
    case 3: *getPhys<PhysicalAddress>(phys) = flo::exchange(physFreeHead3, phys); return;
    case 4: *getPhys<PhysicalAddress>(phys) = flo::exchange(physFreeHead4, phys); return;
    case 5: *getPhys<PhysicalAddress>(phys) = flo::exchange(physFreeHead5, phys); return;
    default: pline("Unkown paging level: ", Decimal{pageLevel}); flo::CPU::hang();
  }
}

flo::PhysicalAddress flo::getPhysicalPage(int pageLevel) {
  auto tryGet =
    [pageLevel](flo::PhysicalAddress &currHead) {
      // Fast path, try to get from current level
      if(currHead())
        return flo::exchange(currHead, *getPhys<PhysicalAddress>(currHead));

      if(pageLevel == 5)
        return PhysicalAddress{0};

      // Slow path, try to get from next level
      auto next = flo::getPhysicalPage(pageLevel + 1);

      if(!next) {
        if(pageLevel == 1) {
          pline("Ran out of physical pages on level ", pageLevel);
          flo::CPU::hang();
        }

        if(!next)
          return PhysicalAddress{0};
      }

      // Woop we got one, let's split it.
      auto stepSize = flo::Paging::pageSizes[pageLevel - 1]; // 0 indexed, we are 1 indexed

      // Return all pages but one
      for(int i = 0; i < flo::Paging::PageTableSize - 1; ++ i) {
        flo::returnPhysicalPage(next, pageLevel);
        next += PhysicalAddress{stepSize};
      }

      return next;
    };

  switch(pageLevel) {
    case 1: return tryGet(physFreeHead1);
    case 2: return tryGet(physFreeHead2);
    case 3: return tryGet(physFreeHead3);
    case 4: return tryGet(physFreeHead4);
    case 5: return tryGet(physFreeHead5);
    default: pline("Unknown page level ", pageLevel); flo::CPU::hang();
  }

  __builtin_unreachable();
  return PhysicalAddress{0};
}

extern "C" void assertAssumptions() {
  auto check =
    [](u64 *value) {
      auto v = *value;
      if(unknownField == v) {
        pline("Unset field ", v, "!!");
        flo::CPU::hang();
      }
    };

  check((u64*)&physFreeHead1);
  check((u64*)&physFreeHead2);
  check((u64*)&physFreeHead3);
  check((u64*)&physFreeHead4);
  check((u64*)&physFreeHead5);
  check((u64*)&physMemRanges);
  check((u64*)&displayWidth);
  check((u64*)&displayHeight);
  check((u64*)&displayPitch);
  check((u64*)&framebuffer);
  check((u64*)&driveNumber);
}

extern "C" void consumeHighPhysicalMemory() {
  for(auto &r: *physMemRanges) {
    pline("Consuming physical memory [", r.begin(), ", ", r.end(), ")");
    flo::consumePhysicalMemory(r.begin, r.end() - r.begin());
  }
}

extern "C" void unmapLowMemory() {
  // Don't return the identity mapped pages
  flo::Paging::unmap<false>(flo::VirtualAddress{0}, flo::Util::mega(512ull));
}

extern "C" void loadKernel() {
  auto loadFail = [](auto &&...vs) {
    pline("Error while loading kernel ELF: ", flo::forward<decltype(vs)>(vs)...);
    flo::CPU::halt();
  };

  kernelELF.verify(flo::move(loadFail));

  u64 addrHigh = 0;

  kernelELF.forEachProgramHeader([&](flo::ELF64::ProgramHeader const &header) {
    u64 sectionAddrHigh = flo::Paging::alignPageUp(header.vaddr() + header.memSz);
    if(sectionAddrHigh > addrHigh)
      addrHigh = sectionAddrHigh;
  });

  addrHigh = flo::Paging::alignPageUp<1>(addrHigh);

  kernelELF.loadOffset = (physBase - flo::VirtualAddress{addrHigh})();
  pline("Kernel needs to be offset by ", kernelELF.loadOffset);

  kernelELF.loadAll();

  kernelEntry = kernelELF.header().entry() + kernelELF.loadOffset;
  pline("Entering kernel...");
}

extern "C" void prepareKernelArgs() {
  kernelArguments.physFreeHead1 = physFreeHead1;
  kernelArguments.physFreeHead2 = physFreeHead2;
  kernelArguments.physFreeHead3 = physFreeHead3;
  kernelArguments.physFreeHead4 = physFreeHead4;
  kernelArguments.physFreeHead5 = physFreeHead5;
  kernelArguments.physBase = physBase;
  kernelArguments.displayWidth = displayWidth;
  kernelArguments.displayHeight = displayHeight;
  kernelArguments.displayPitch = displayPitch;
  kernelArguments.framebuffer = framebuffer;
  kernelArguments.driveNumber = driveNumber;
}
