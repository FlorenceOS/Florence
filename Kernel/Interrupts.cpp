#include "flo/Assert.hpp"
#include "flo/Bitfields.hpp"
#include "flo/Interrupts.hpp"
#include "flo/IO.hpp"
#include "flo/Kernel.hpp"
#include "flo/Memory.hpp"

extern "C" void *exceptionHandlers[0x20];

namespace flo::Interrupts {
  namespace {
    auto pline = flo::makePline<false>("[INTERRUPTS]");

    struct IDTEntry {
      u16 addrLow = 0;
      u16 selector = 0;
      u8  ist = 0;

      union Attrib {
        u8 repr = 0;
        flo::Bitfield<0, 4, u8> gateType;
        flo::Bitfield<4, 1, u8> storage;
        flo::Bitfield<5, 2, u8> privLevel;
        flo::Bitfield<7, 1, u8> present;
      };

      Attrib attributes;
      u16 addrMid = 0;
      u32 addrHigh = 0;
      u32 zeroes = 0;
    };

    static_assert(sizeof(IDTEntry) == 0x10);

    IDTEntry encode(void *handler, IDTEntry::Attrib attributes, u8 ist = 0) {
      union Addr {
        void *addr;
        flo::Bitfield<0,  16> addrLow;
        flo::Bitfield<16, 16> addrMid;
        flo::Bitfield<32, 32> addrHigh;
      };

      Addr a;
      a.addr = handler;

      IDTEntry result{};

      result.addrLow  = a.addrLow;
      result.addrMid  = a.addrMid;
      result.addrHigh = a.addrHigh;

      result.attributes = attributes;

      result.selector = 0x8; // 64 bit code

      result.ist = ist;

      return result;
    }

    struct IDT {
      IDTEntry entries[0x100];
    };

    static_assert(sizeof(IDT) == 0x1000);

    IDT *idt = nullptr;

    struct ErrorFrame {
      u64 r15;
      u64 r14;
      u64 r13;
      u64 r12;
      u64 r11;
      u64 r10;
      u64 r9;
      u64 r8;
      u64 rdi;
      u64 rsi;
      u64 rbp;
      u64 rdx;
      u64 rcx;
      u64 rbx;
      u64 rax;
      u64 interruptNumber;
      u64 errorCode;
      u64 rip;
      u64 cs;
      u64 eflags;
      u64 rsp; 
      u64 ss;
    };

    char const *exceptionToString(u64 exceptionNumber) {
      switch(exceptionNumber) {
      case 0x00: return "Divide by zero";
      case 0x01: return "Debug";
      case 0x02: return "NMI";
      case 0x03: return "Breakpoint";
      case 0x04: return "Overflow";
      case 0x05: return "Bound range exceeded";
      case 0x06: return "Invalid opcode";
      case 0x07: return "Device not available";
      case 0x08: return "Double fault";
      case 0x0A: return "Invalid TSS";
      case 0x0B: return "Segment not present";
      case 0x0C: return "Stack-segment fault";
      case 0x0D: return "General protection fault";
      case 0x0E: return "Page fault";
      case 0x10: return "x87 Floating-point exception";
      case 0x11: return "Alignment check";
      case 0x12: return "Machine check";
      case 0x13: return "SIMD Floating-point exception";
      case 0x14: return "Virtualization exception";
      case 0x1E: return "Security exception";
      default:   return "Unknown";
      }
    }

    bool isFatal(u64 exceptionNumber) {
      switch(exceptionNumber) {
      case 0x00: return false;
      case 0x01: return false;
      case 0x02: return false;
      case 0x03: return false;
      case 0x04: return false;
      case 0x05: return false;
      case 0x06: return false;
      case 0x07: return false;
      case 0x08: return true;
      case 0x0A: return true;
      case 0x0B: return true;
      case 0x0C: return true;
      case 0x0D: return true;
      case 0x0E: return true;
      case 0x10: return false;
      case 0x11: return false;
      case 0x12: return true;
      case 0x13: return false;
      case 0x14: return true;
      case 0x1E: return true;
      default:   return true;
      }
    }
  }
}

extern "C" void exceptionHandler() {
  flo::Interrupts::ErrorFrame *frame;
  __asm__(
    "lea 16(%%rbp), %0\n"
    : "=r"(frame)
  );

  flo::Interrupts::pline("CPU exception ", frame->interruptNumber, " (",
    flo::Interrupts::exceptionToString(frame->interruptNumber), ") at DIP=", flo::deslide(frame->rip));
  flo::Interrupts::pline("In function ", flo::symbolName(frame->rip));
  flo::Interrupts::pline("RAX=", frame->rax, " RBX=", frame->rbx, " RCX=", frame->rcx, " RDX=", frame->rdx);
  flo::Interrupts::pline("RSI=", frame->rsi, " RDI=", frame->rdi, " RBP=", frame->rbp, " RSP=", frame->rsp);
  flo::Interrupts::pline("R8 =", frame->r8 , " R9 =", frame->r9 , " R10=", frame->r10, " R11=", frame->r11);
  flo::Interrupts::pline("R12=", frame->r12, " R13=", frame->r13, " R14=", frame->r14, " R15=", frame->r15);
  flo::Interrupts::pline("SS =", frame->ss , " CS =", frame->cs,  " RIP=", frame->rip, " EC =", frame->errorCode);

  if(flo::Interrupts::isFatal(frame->interruptNumber))
    assert_not_reached();
  else
    flo::printBacktrace();
}

void flo::Interrupts::initialize() {
  flo::Interrupts::idt = Allocator<flo::Interrupts::IDT>::allocate();

  flo::Interrupts::IDTEntry::Attrib exceptionAttributes;
  exceptionAttributes.gateType = 0xf;
  exceptionAttributes.storage = 0;
  exceptionAttributes.privLevel = 0;
  exceptionAttributes.present = 1;

  for(uSz i = 0; i < flo::Util::arrSz(exceptionHandlers); ++i)
    flo::Interrupts::idt->entries[i] = flo::Interrupts::encode(exceptionHandlers[i], exceptionAttributes);

  struct {
    u16 limit = sizeof(flo::Interrupts::IDT) - 1;
    u64 base = (u64)flo::Interrupts::idt;
  } __attribute__((packed)) idtr;

  __asm__("lidt %0" : : "m"(idtr));

  __asm__("int $3");
}
