#include "flo/IO.hpp"
#include "flo/Kernel.hpp"

namespace {
  constexpr bool quiet = false;
  auto pline = flo::makePline<quiet>("[FLORK] ");
  flo::KernelArguments arguments;
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

u8 *flo::getPtrPhys(flo::PhysicalAddress paddr) {
  return (u8 *)(paddr() + arguments.physBase());
}

u8 *flo::getPtrVirt(flo::VirtualAddress virt) {
  return (u8 *)virt();
}

void flo::returnPhysicalPage(flo::PhysicalAddress phys, int pageLevel) {
  switch(pageLevel) {
    case 1: *getPhys<PhysicalAddress>(phys) = flo::exchange(arguments.physFreeHead1, phys); return;
    case 2: *getPhys<PhysicalAddress>(phys) = flo::exchange(arguments.physFreeHead2, phys); return;
    case 3: *getPhys<PhysicalAddress>(phys) = flo::exchange(arguments.physFreeHead3, phys); return;
    case 4: *getPhys<PhysicalAddress>(phys) = flo::exchange(arguments.physFreeHead4, phys); return;
    case 5: *getPhys<PhysicalAddress>(phys) = flo::exchange(arguments.physFreeHead5, phys); return;
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
    case 1: return tryGet(arguments.physFreeHead1);
    case 2: return tryGet(arguments.physFreeHead2);
    case 3: return tryGet(arguments.physFreeHead3);
    case 4: return tryGet(arguments.physFreeHead4);
    case 5: return tryGet(arguments.physFreeHead5);
    default: pline("Unknown page level ", pageLevel); flo::CPU::hang();
  }

  __builtin_unreachable();
  return PhysicalAddress{0};
}

extern "C"
void kernelMain() {
  pline("Hello ELF kernel land");
  pline("My ELF is loaded at ", arguments.elfImage->data, " with size ", arguments.elfImage->size);
  pline("Physical base is at ", (void *)arguments.physBase());
  pline("  Best regards, 0x", (void *)&kernelMain);
}

// Must be reachable from assembly
extern "C" {
  flo::KernelArguments *kernelArgumentPtr = nullptr;
}

extern "C" void loadKernelArugments() {
  arguments = *kernelArgumentPtr;
}
