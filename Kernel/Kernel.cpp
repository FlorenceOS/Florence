#include "flo/Kernel.hpp"

#include "flo/CPU.hpp"
#include "flo/Memory.hpp"

#include "Kernel/ACPI.hpp"
#include "Kernel/Interrupts.hpp"
#include "Kernel/IO.hpp"
#include "Kernel/PCI.hpp"

#include "Kernel/Drivers/Gfx/GenericVGA.hpp"

#include "Ints.hpp"
#include "flo/Containers/Optional.hpp"

// Must be reachable from assembly
extern "C" {
  flo::KernelArguments *kernelArgumentPtr = nullptr;
}

// Comes from linker
extern "C" u8 kernelStart[];
extern "C" u8 kernelEnd[];

namespace {
  flo::ELF64Image kernelElf;

  flo::KernelArguments arguments = []() {
    flo::KernelArguments args;
    // Kill the pointer after using it, we shouldn't touch it.
    args = flo::move(*flo::exchange(kernelArgumentPtr, nullptr));
    return args;
  }();

  constexpr bool quiet = false;
  auto pline = flo::makePline<quiet>("[FLORK]");
  bool enable_vga = false;

  auto consumeKernelArguments = []() {
    // Relocate physFree
    flo::physFree = *flo::exchange(arguments.physFree, nullptr);

    char const *protocol_name = "UNKNOWN";

    switch(arguments.type) {
    case flo::KernelArguments::BootType::Stivale:
      enable_vga = false;
      protocol_name = "Stivale";
      break;

    case flo::KernelArguments::BootType::Florence:
      Kernel::IO::VGA::currX = *flo::exchange(arguments.flo_boot.vgaX, nullptr);
      Kernel::IO::VGA::currY = *flo::exchange(arguments.flo_boot.vgaY, nullptr);
      enable_vga = true;
      Kernel::GenericVGA::set_text_mode();
      protocol_name = "Florence";
      break;

    default:
      assert_not_reached();
    }

    pline("Using boot protocol ", protocol_name);

    return flo::nullopt;
  }();
}

extern "C" void initializeVmm() {
  auto giveVirtRange = [](u8 *begin, u8 *end) {
    begin = (u8 *)flo::Paging::align_page_up((uptr)begin);
    end   = (u8 *)flo::Paging::align_page_down((uptr)end);
    flo::returnVirtualPages(begin, (end - begin)/flo::Paging::PageSize<1>);
  };

  if(kernelStart < flo::getVirt<u8>(flo::Paging::virt_limit)) {
    // Kernel is in bottom half
    giveVirtRange((u8 *)flo::Util::giga(4ull), kernelStart);
    giveVirtRange((u8 *)arguments.physEnd(), (u8 *)(flo::Paging::virt_limit() >> 1));

    giveVirtRange((u8 *)~((flo::Paging::virt_limit() >> 1) - 1), (u8 *)~(flo::Util::giga(4ull) - 1));
  }
  else {
    giveVirtRange((u8 *)flo::Util::giga(4ull), (u8 *)(flo::Paging::virt_limit() >> 1));

    // Kernel is in top half
    giveVirtRange((u8 *)~((flo::Paging::virt_limit() >> 1) - 1), kernelStart);
    giveVirtRange((u8 *)arguments.physEnd(), (u8 *)~(flo::Util::giga(4ull) - 1));
  }

  // Relocate kernel ELF
  kernelElf = *arguments.elfImage;
  arguments.elfImage = &kernelElf;

  // Relocate kernel ELF data
  auto const kernel_new_location = flo::malloc_size(arguments.elfImage->size);
  __builtin_memcpy(kernel_new_location, arguments.elfImage->data, arguments.elfImage->size);

  kernelElf.data = (u8 *)kernel_new_location;

  // Symbols have to be reinitialized as the image has moved in memory
  kernelElf.initSymbols();

  // Unmap all of bottom 4 GB as we want all of it unmapped.
  flo::Paging::unmap({
    .virt = flo::VirtualAddress{0},
    .size = 1ull << 32,
    // Reclaim these pages, the kernel loader is dynamically allocated.
    .recycle_pages = true,
  });
}

void flo::feedLine() {
  if constexpr(quiet)
    return;

  if(enable_vga)
    Kernel::IO::VGA::feedLine();
  Kernel::IO::Debugout::feedLine();
}

void flo::putchar(char c) {
  if constexpr(quiet)
    return;

  if(c == '\n')
    return feedLine();

  if(enable_vga)
    Kernel::IO::VGA::putchar(c);
  Kernel::IO::Debugout::write(c);
}

void flo::setColor(flo::TextColor col) {
  if constexpr(quiet)
    return;

  if(enable_vga)
    Kernel::IO::VGA::setColor(col);
  Kernel::IO::Debugout::setColor(col);
}

u8 *flo::getPtrPhys(flo::PhysicalAddress paddr) {
  return (u8 *)(paddr() + arguments.physBase());
}

u8 *flo::getPtrVirt(flo::VirtualAddress virt) {
  return (u8 *)virt();
}

void panic(char const *reason) {
  pline(flo::TextColor::red, "Kernel panic! Reason: ", flo::TextColor::red, reason);

  flo::printBacktrace();

  flo::CPU::hang();
}

#include "flo/Mutex.hpp"

flo::Mutex m;

extern "C"
void kernelMain() {
  Kernel::Interrupts::initialize();
  if(arguments.type == flo::KernelArguments::BootType::Stivale) {
    Kernel::ACPI::initialize(arguments.stivale_boot.rsdp);
    Kernel::GenericVGA::set_vesa_fb(arguments.stivale_boot.fb, arguments.stivale_boot.pitch, arguments.stivale_boot.width, arguments.stivale_boot.height, arguments.stivale_boot.bpp);
  }
  else
    Kernel::ACPI::initialize();
  Kernel::PCI::initialize();
}

uptr flo::deslide(uptr addr) {
  return addr - arguments.elfImage->loadOffset;
}

char const *flo::symbolName(uptr addr) {
  auto symbol = arguments.elfImage->lookupSymbol(addr);
  auto symbolName = symbol ? arguments.elfImage->symbolName(*symbol) : nullptr;
  return symbolName ?: "[NO NAME]";
}

void flo::printBacktrace() {
  auto frame = flo::getStackFrame();

  pline("Backtrace: ");
  flo::getStackTrace(frame, [](auto &stackFrame) {
    pline("[", flo::deslide(stackFrame.retaddr), "/", stackFrame.retaddr, "]: ", flo::symbolName(stackFrame.retaddr));
  });
}

void flo::printBacktrace(uptr basePointer) {
  pline("Backtrace: ");
  flo::getStackTrace(basePointer, [](auto &stackFrame) {
    pline("[", flo::deslide(stackFrame.retaddr), "/", stackFrame.retaddr, "]: ", flo::symbolName(stackFrame.retaddr));
  });
}
