#include "flo/IO.hpp"
#include "flo/Kernel.hpp"

#include "LibFlo.cpp"

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

    // @TODO: relocate ELF

    // @TODO: initialize framebuffer
    return flo::nullopt;
  }();
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


void panic(char const *reason) {
  pline(flo::IO::Color::red, "Kernel panic! Reason: ", flo::IO::Color::red, reason);

  auto frame = flo::getStackFrame();

  pline("Backtrace: ");
  flo::getStackTrace(frame, [](auto &stackFrame) {
    auto symbol = arguments.elfImage->lookupSymbol(stackFrame.retaddr);
    auto symbolName = symbol ? arguments.elfImage->symbolName(*symbol) : nullptr;
    pline(symbolName ?: "[NO NAME]", ": ", stackFrame.retaddr - arguments.elfImage->loadOffset);
  });

  flo::CPU::halt();
}

namespace Fun::things {
  void foo() {
    panic("Failed successfully");
  }
}

extern "C"
void kernelMain() {
  pline("Hello ELF kernel land");
  pline("My ELF is loaded at ", arguments.elfImage->data, " with size ", arguments.elfImage->size);
  pline("Physical base is at ", (void *)arguments.physBase());
  pline("  Best regards, 0x", (void *)&kernelMain);

  Fun::things::foo();
}
