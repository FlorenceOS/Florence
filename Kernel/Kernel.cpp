#include "flo/ACPI.hpp"
#include "flo/Interrupts.hpp"
#include "flo/IO.hpp"
#include "flo/Kernel.hpp"
#include "flo/Memory.hpp"
#include "flo/PCI.hpp"

// Must be reachable from assembly
extern "C" {
  flo::KernelArguments *kernelArgumentPtr = nullptr;
}

namespace {
  flo::KernelArguments arguments = []() {
    flo::KernelArguments args;
    // Kill the pointer after using it, we shouldn't touch it.
    args = flo::move(*flo::exchange(kernelArgumentPtr, nullptr));
    return args;
  }();

  constexpr bool quiet = false;
  auto pline = flo::makePline<quiet>("[FLORK]");

  auto consumeKernelArguments = []() {
    // Relocate physFree
    flo::physFree = *flo::exchange(arguments.physFree, nullptr);
    flo::IO::VGA::currX = *flo::exchange(arguments.vgaX, nullptr);
    flo::IO::VGA::currY = *flo::exchange(arguments.vgaY, nullptr);

    // @TODO: relocate ELF

    // @TODO: initialize framebuffer
    return flo::nullopt;
  }();
}

extern "C" u8 kernelStart[];
extern "C" u8 kernelEnd[];


void flo::feedLine() {
  if constexpr(quiet)
    return;

  flo::IO::VGA::feedLine();
  flo::IO::serial1.feedLine();
}

void flo::putchar(char c) {
  if constexpr(quiet)
    return;

  if(c == '\n')
    return feedLine();

  flo::IO::VGA::putchar(c);
  flo::IO::serial1.write(c);
}

void flo::setColor(flo::IO::Color col) {
  if constexpr(quiet)
    return;

  flo::IO::VGA::setColor(col);
  flo::IO::serial1.setColor(col);
}

u8 *flo::getPtrPhys(flo::PhysicalAddress paddr) {
  return (u8 *)(paddr() + arguments.physBase());
}

u8 *flo::getPtrVirt(flo::VirtualAddress virt) {
  return (u8 *)virt();
}


void panic(char const *reason) {
  pline(flo::IO::Color::red, "Kernel panic! Reason: ", flo::IO::Color::red, reason);

  flo::printBacktrace();

  flo::CPU::hang();
}

namespace Fun::things {
  void foo() {
    panic("Failed successfully");
  }
}

namespace {
  void initializeFreeVmm() {
    auto giveVirtRange = [](u8 *begin, u8 *end) {
      begin = (u8 *)flo::Paging::alignPageUp(flo::VirtualAddress{(u64)begin})();
      end   = (u8 *)flo::Paging::alignPageDown(flo::VirtualAddress{(u64)end})();
      flo::returnVirtualPages(begin, (end - begin)/flo::Paging::PageSize<1>);
    };

    if(kernelStart < flo::getVirt<u8>(flo::Paging::maxUaddr)) {
      // Kernel is in bottom half
      giveVirtRange((u8 *)flo::Util::giga(4ull), kernelStart);
      giveVirtRange((u8 *)arguments.physEnd(), (u8 *)(flo::Paging::maxUaddr() >> 1));

      giveVirtRange((u8 *)~((flo::Paging::maxUaddr() >> 1) - 1), (u8 *)~(flo::Util::giga(4ull) - 1));
    }
    else {
      giveVirtRange((u8 *)flo::Util::giga(4ull), (u8 *)(flo::Paging::maxUaddr() >> 1));

      // Kernel is in top half
      giveVirtRange((u8 *)~((flo::Paging::maxUaddr() >> 1) - 1), kernelStart);
      giveVirtRange((u8 *)arguments.physEnd(), (u8 *)~(flo::Util::giga(4ull) - 1));
    }
  }
}

extern "C"
void kernelMain() {
  pline("Starting drivers...");

  initializeFreeVmm();

  flo::Interrupts::initialize();
  flo::ACPI::initialize();
  flo::PCI::initialize();

  Fun::things::foo();
}

uptr flo::deslide(uptr addr) {
  if((uptr)kernelStart <= addr && addr < (uptr)kernelEnd)
    return addr - arguments.elfImage->loadOffset;
  return addr;
}

void flo::printBacktrace() {
  auto frame = flo::getStackFrame();

  pline("Backtrace: ");
  flo::getStackTrace(frame, [](auto &stackFrame) {
    auto symbol = arguments.elfImage->lookupSymbol(stackFrame.retaddr);
    auto symbolName = symbol ? arguments.elfImage->symbolName(*symbol) : nullptr;
    pline(symbolName ?: "[NO NAME]", ": ", flo::deslide(stackFrame.retaddr));
  });
}
