#include "flo/ACPI.hpp"
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
    pline("Oh come on! Whatever. Leave me. I will love you forever.");
  }

  void test_flag(char *flag_str) {
    // [SSM{]
    if(!flo::Util::memeq(flag_str, "SSM{", 4))
      panic("Are you even trying?? I can't handle this, sorry. I'm panicking.");

    auto bad_flag = []() {
      pline("Instance of BadFlagException thrown. Nah, just kidding. But your flag is wrong.");
      flo::CPU::hang(); // No panic. Just hang. No backtrace for you.
    };

    flag_str += 4;

    // SSM{[w]
    // This works only because KASLR uses a static seed in this configuration
    if(*flag_str != 'a' + ((arguments.physBase() >> (6 * 4)) & 0xFF)) {
      //pline("Failed on KASLR check which requires ", 'a' + ((arguments.physBase() >> (6 * 4)) & 0xFF));
      bad_flag();
    }

    flag_str += 1;

    {
      int numCorrect = 0;
      int numWrong = 0;

      auto test = [&](uSz ind) {
        if(numCorrect != ind)
          ++numWrong;
        else
          ++numCorrect;
        ++flag_str;
      };

      another_one:
      switch(*flag_str) {
      // SSM{w[e]
      case 'e':
        test(0);
        goto another_one;
      // SSM{we[_]
      case '_':
        test(1);
        goto another_one;
      // SSM{we_[m]
      case 'm':
        test(2);
        goto another_one;
      // SSM{we_m[u]
      case 'u':
        test(3);
        goto another_one;
      // SSM{we_mu[s]
      case 's':
        test(4);
        goto another_one;
      // SSM{we_mus[t]
      case 't':
        test(5);
        break;
      default:
        ++numWrong;
        break;
      }

      if(numCorrect != 6 || numWrong) {
        //pline("Annoying check failed. Sucks to be you.");
        bad_flag();
      }
    }

    auto memfrobnicatornator = [](char *ptr, u8 sz) {
      char val = 42;
      for(int i = 0; i < sz; ++ i)
        *ptr++ ^= val++;
    };

    // SSM{we_must[_go_deeeeeeeeee]
    memfrobnicatornator(flag_str, 15);
    if(!flo::Util::memeq(flag_str, "uLCrJJUTWVQPSR]", 15)) {
      //pline("Aw, you failed the (almost) memfrob :(");
      bad_flag();
    }

    flag_str += 15;

    // SSM{we_must_go_deeeeeeeeee[_]
    if(69 * (u64)*flag_str++ != 69 * (u64)'_') {
      //pline("Failed the 69 check. Sad.");
      bad_flag();
    }

    // SSM{we_must_go_deeeeeeeeee_[n]
    if(420 * (u64)*flag_str++ != 420 * (u64)'n') {
      //pline("Failed the 420 check. Sad.");
      bad_flag();
    }

    // SSM{we_must_go_deeeeeeeeee_n[ope}]
    if(1337 * (u64)*(u32 *)flag_str != 1337 * (u64)*(u32 const *)"ope}") {
      //pline("Failed the 1337 check. Sad.");
      bad_flag();
    }

    flag_str += 4;

    if(*(flag_str))
      bad_flag();

    // Flag looks good to me, just return.
  }

  void request_flag() {
    char flag[128]{};

    pline("Give me your flag so that I have something to remember you by.");
    auto it = flag;
    while(1) {
      auto input = flo::IO::serial1.read();

      if(input == '\r' || input == '\n') {
        *it = '\0';
        flo::IO::serial1.write('\n');
        break;
      }

      if(it != flo::end(flag) - 1) {
        *it++ = input;
        flo::IO::serial1.write(input);
      }
    }

    pline("Oh my god, this flag: ", flag);
    test_flag(flag);
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
      giveVirtRange(kernelEnd, (u8 *)flo::Paging::maxUaddr());

      giveVirtRange((u8 *)~(flo::Paging::maxUaddr() - 1), (u8 *)~(flo::Util::giga(4ull) - 1));
    }
    else {
      giveVirtRange((u8 *)flo::Util::giga(4ull), (u8 *)flo::Paging::maxUaddr());

      // Kernel is in top half
      giveVirtRange((u8 *)~(flo::Paging::maxUaddr() - 1), kernelStart);
      giveVirtRange(kernelEnd, (u8 *)~(flo::Util::giga(4ull) - 1));
    }
  }
}

extern "C"
void kernelMain() {
  initializeFreeVmm();

  flo::ACPI::initialize();
  //flo::PCI::initialize();

  Fun::things::request_flag();
  //char str[] { "AAAA" };
  //char str[] { "SSM{we_must_go_deeeeeeeeee_nope}" };
  //char str[] { "SSM{}" };
  //Fun::things::test_flag(str);

  Fun::things::foo();
}

void flo::printBacktrace() {
  auto frame = flo::getStackFrame();

  pline("Backtrace: ");
  flo::getStackTrace(frame, [](auto &stackFrame) {
    auto symbol = arguments.elfImage->lookupSymbol(stackFrame.retaddr);
    auto symbolName = symbol ? arguments.elfImage->symbolName(*symbol) : nullptr;
    pline(symbolName ?: "[NO NAME]", ": ", stackFrame.retaddr - arguments.elfImage->loadOffset);
  });
}
