#include "flo/Assert.hpp"
#include "flo/Bitfields.hpp"
#include "flo/CPU.hpp"
#include "flo/Kernel.hpp"
#include "flo/Memory.hpp"
#include "flo/Multitasking.hpp"

#include "Kernel/Interrupts.hpp"
#include "Kernel/IO.hpp"

extern "C" void *exceptionHandlers[0x20];
extern "C" void *irqHandlers[0x10];
extern "C" void *schedulerCalls[0x2];

namespace Kernel::Interrupts {
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
      uptr r15;
      uptr r14;
      uptr r13;
      uptr r12;
      uptr r11;
      uptr r10;
      uptr r9;
      uptr r8;
      uptr rdi;
      uptr rsi;
      uptr rbp;
      uptr rdx;
      uptr rcx;
      uptr rbx;
      uptr rax;
      uptr interruptNumber;
      uptr errorCode;
      uptr rip;
      uptr cs;
      uptr eflags;
      uptr rsp; 
      uptr ss;
    };

    enum ExceptionNumber: uptr {
      DivideZero = 0x00,
      Debug = 0x01,
      NMI = 0x02,
      Breakpoint = 0x03,
      Overflow = 0x04,
      BoundRangeExceeded = 0x05,
      InvalidOpcode = 0x06,
      DeviceNotAvailable = 0x07,
      DoubleFault = 0x08,
      InvalidTSS = 0x0A,
      SegmentNotPresent = 0x0B,
      StackSegmentationFault = 0x0C,
      GeneralProtectionFault = 0x0D,
      PageFault = 0x0E,
      x87FloatingPointException = 0x10,
      AlignmentCheck = 0x11,
      MachineCheck = 0x12,
      SIMDFloatingPointException = 0x13,
      VirtualizationException = 0x14,
      SecurityException = 0x1E,
    };

    char const *exceptionToString(u64 exceptionNumber) {
      switch(exceptionNumber) {
      case DivideZero:
        return "Divide by zero";
      case Debug:
        return "Debug";
      case NMI:
        return "NMI";
      case Breakpoint:
        return "Breakpoint";
      case Overflow:
        return "Overflow";
      case BoundRangeExceeded:
        return "Bound range exceeded";
      case InvalidOpcode:
        return "Invalid opcode";
      case DeviceNotAvailable:
        return "Device not available";
      case DoubleFault:
        return "Double fault";
      case InvalidTSS:
        return "Invalid TSS";
      case SegmentNotPresent:
        return "Segment not present";
      case StackSegmentationFault:
        return "Stack-segment fault";
      case GeneralProtectionFault:
        return "General protection fault";
      case PageFault:
        return "Page fault";
      case x87FloatingPointException:
        return "x87 Floating-point exception";
      case AlignmentCheck:
        return "Alignment check";
      case MachineCheck:
        return "Machine check";
      case SIMDFloatingPointException:
        return "SIMD Floating-point exception";
      case VirtualizationException:
        return "Virtualization exception";
      case SecurityException:
        return "Security exception";
      default:
        return "Unknown";
      }
    }

    bool isFatal(u64 exceptionNumber) {
      switch(exceptionNumber) {
      case DivideZero:
      case Debug:
      case NMI:
      case Overflow:
      case BoundRangeExceeded:
      case DeviceNotAvailable:
      case x87FloatingPointException:
      case AlignmentCheck:
      case SIMDFloatingPointException:
        return false;
      case Breakpoint:
      case InvalidOpcode:
      case DoubleFault:
      case InvalidTSS:
      case SegmentNotPresent:
      case StackSegmentationFault:
      case GeneralProtectionFault:
      case PageFault:
      case MachineCheck:
      case VirtualizationException:
      case SecurityException:
      default:
        return true;
      }
    }

    void dumpFrame(Kernel::Interrupts::ErrorFrame *frame) {
      Kernel::Interrupts::pline("RAX=", frame->rax, " RBX=", frame->rbx, " RCX=", frame->rcx, " RDX=", frame->rdx);
      Kernel::Interrupts::pline("RSI=", frame->rsi, " RDI=", frame->rdi, " RBP=", frame->rbp, " RSP=", frame->rsp);
      Kernel::Interrupts::pline("R8 =", frame->r8 , " R9 =", frame->r9 , " R10=", frame->r10, " R11=", frame->r11);
      Kernel::Interrupts::pline("R12=", frame->r12, " R13=", frame->r13, " R14=", frame->r14, " R15=", frame->r15);
      Kernel::Interrupts::pline("SS =", frame->ss , " CS =", frame->cs,  " RIP=", frame->rip, " EC =", frame->errorCode);
    }

    void exceptionHandler(Kernel::Interrupts::ErrorFrame *frame) {
      Kernel::Interrupts::pline("CPU exception ", frame->interruptNumber, " (",
        Kernel::Interrupts::exceptionToString(frame->interruptNumber), ") at [", flo::deslide(frame->rip), "/", frame->rip, "]");
      Kernel::Interrupts::pline("In function ", flo::symbolName(frame->rip));
      dumpFrame(frame);

      if(Kernel::Interrupts::isFatal(frame->interruptNumber)) {
        flo::printBacktrace(frame->rbp);
        flo::CPU::hang();
      }
    }

    struct Task {
      ErrorFrame ef;
      Task *next = nullptr;
      flo::Function<void(flo::TaskControlBlock &)> callable;

      flo::TaskControlBlock controlBlock;
      void *stack;

      Task(char const *name) {
        flo::Util::setmem((u8 *)&ef, 0, sizeof(ef));
        controlBlock.name = name;
      }

      ~Task() {
        if(stack)
          freeStack((void *)stack);
      }

      void saveRegs(ErrorFrame *stackFrame) {
        flo::Util::copymem((u8 *)&ef, (u8 *)stackFrame, sizeof(ef));
      }

      void restoreRegs(ErrorFrame *stackFrame) {
        flo::Util::copymem((u8 *)stackFrame, (u8 *)&ef, sizeof(ef));
      }
    };

    struct TaskQueue {
      Task *front = nullptr;
      Task *back = nullptr;

      void assert_invariant() const {
        assert(front ? !!back : !back);
      }

      Task *peek() const {
        assert_invariant();
        return front;
      }

      Task *yield(Task *task) {
        assert_invariant();
        insertBack(task);
        return getAndPop();
      }

      Task *getAndPop() {
        assert_invariant();
        if(!front->next)
          back = nullptr;
        return flo::exchange(front, front->next);
      }

      void insertFront(Task *task) {
        assert_invariant();

        if(!front)
          back = task;

        task->next = flo::exchange(front, task);

        assert(front && back);
      }

      void insertBack(Task *task) {
        assert_invariant();

        if(front)
          flo::exchange(back, task)->next = task;
        else
          front = back = task;

        task->next = nullptr;

        assert(front && back);
      }
    };

    inline TaskQueue taskQueue;

    void setCurrentTask(Task *task) {
      assert(task);
      flo::CPU::KernelGSBase = (uptr)task;
    }

    Task *getCurrentTask() {
      return (Task *)(uptr)flo::CPU::KernelGSBase;
    }

    void taskEntry() {
      getCurrentTask()->callable(getCurrentTask()->controlBlock);
      flo::exit();
    }

    void waitForInterrupt() {
      asm("sti\nhlt\ncli");
    }

    void doYieldImpl(Kernel::Interrupts::ErrorFrame *frame) {
      if(!taskQueue.peek()) { // No other tasks to execute.
        waitForInterrupt();
        return;
      }

      auto task = getCurrentTask();

      // We don't want any non-runnable tasks in the queue
      assert(task->controlBlock.isRunnable);

      task->saveRegs(frame);

      task = taskQueue.yield(task);

      setCurrentTask(task);

      task->restoreRegs(frame);

      return;
    }

    void doKillTask(Kernel::Interrupts::ErrorFrame *frame) {
      while(!taskQueue.peek()) // No other task to execute
        waitForInterrupt();

      auto old_task = getCurrentTask();

      auto task = taskQueue.getAndPop();

      setCurrentTask(task);

      task->restoreRegs(frame);

      old_task->~Task();
      flo::Allocator<Task>::deallocate(old_task);
      return;      
    }

    flo::Array<flo::Function<void()>, 0x10> registeredHandlerFuncs;

    void doEOI() {
      pline("FIXME: EOI");
    }
  }
}

extern "C" void interruptHandler() {
  Kernel::Interrupts::ErrorFrame *frame;
  __asm__(
    "lea 16(%%rbp), %0\n"
    : "=r"(frame)
  );

  switch(frame->interruptNumber) {
  case 0x00 ... 0x1F:
    Kernel::Interrupts::pline("EXCEPTION TIME");
    Kernel::Interrupts::exceptionHandler(frame);
    break;

  case 0x30:
    return Kernel::Interrupts::doYieldImpl(frame);

  case 0x31:
    return Kernel::Interrupts::doKillTask(frame);

  case 0x20 ... 0x2F:
    {
      auto &handler = Kernel::Interrupts::registeredHandlerFuncs[frame->interruptNumber - 0x20];
      if(handler)
        return handler();
      Kernel::Interrupts::doEOI();
    }

    [[fallthrough]];
  default:
    Kernel::Interrupts::pline("Unhandled IRQ ", frame->interruptNumber, "!!");
    assert_not_reached();
    break;
  }
}

template<int ind> u8 picPortBase;
template<> u8 picPortBase<1> = 0x20;
template<> u8 picPortBase<2> = 0xa0;

template<int ind> u8 picPortCommand = picPortBase<ind>;
template<int ind> u8 picPortData = picPortBase<ind> + 1;

void Kernel::Interrupts::initialize() {
  Kernel::Interrupts::idt = flo::Allocator<Kernel::Interrupts::IDT>::allocate();

  // CPU exceptions
  Kernel::Interrupts::IDTEntry::Attrib attributes;
  attributes.gateType = 0xF;
  attributes.storage = 0;
  attributes.privLevel = 0;
  attributes.present = 1;

  uSz i = 0;
  for(uSz j = 0; j < flo::Util::arrSz(exceptionHandlers); ++j, ++i)
    Kernel::Interrupts::idt->entries[i] = Kernel::Interrupts::encode(exceptionHandlers[j], attributes);

  // IRQs
  attributes.gateType = 0xE;

  for(uSz j = 0; j < flo::Util::arrSz(irqHandlers); ++j, ++i)
    Kernel::Interrupts::idt->entries[i] = Kernel::Interrupts::encode(irqHandlers[j], attributes);

  // Software yield
  for(uSz j = 0; j < 0x10; ++j, ++i)
    if(j < flo::Util::arrSz(schedulerCalls))
      Kernel::Interrupts::idt->entries[i] = Kernel::Interrupts::encode(schedulerCalls[j], attributes);

  auto mainTask = flo::Allocator<Kernel::Interrupts::Task>::allocate();
  new (mainTask) Task{"Main task"};
  mainTask->controlBlock.isRunnable = true;
  mainTask->stack = nullptr;
  setCurrentTask(mainTask);

  // https://wiki.osdev.org/PIC#Initialisation
  Kernel::IO::outb(picPortCommand<1>, 0x11);
  Kernel::IO::outb(picPortCommand<2>, 0x11);
  Kernel::IO::outb(picPortData<1>, 0x20);
  Kernel::IO::outb(picPortData<2>, 0x28);
  Kernel::IO::outb(picPortData<1>, 0b0000'0100);
  Kernel::IO::outb(picPortData<2>, 0b0000'0010);

  Kernel::IO::outb(picPortData<1>, 0x01);
  Kernel::IO::outb(picPortData<2>, 0x01);

  // Mask out all interrupts
  Kernel::IO::outb(picPortData<1>, 0xF);
  Kernel::IO::outb(picPortData<2>, 0xF);

  // Enable interrupts
  struct {
    u16 limit = sizeof(Kernel::Interrupts::IDT) - 1;
    u64 base = (u64)Kernel::Interrupts::idt;
  } __attribute__((packed)) idtr;

  asm("lidt %0" : : "m"(idtr));
}

void flo::yield() {
  asm("int $48");
}

void flo::exit() {
  asm("int $49");
}

flo::TaskControlBlock &flo::makeTask(char const *taskName, flo::Function<void(TaskControlBlock &)> &&func) {
  auto task = flo::Allocator<Kernel::Interrupts::Task>::allocate();
  new (task) Kernel::Interrupts::Task{taskName};
  task->stack = makeStack();
  task->callable = flo::move(func);
  task->ef.rip = (uptr)&Kernel::Interrupts::taskEntry;
  task->ef.rbp = task->ef.rsp = (uptr)task->stack;
  task->ef.ss = 0x10;
  task->ef.cs = 0x08;
  Kernel::Interrupts::taskQueue.insertBack(task);

  return task->controlBlock;
}

flo::threadID flo::getCurrentThread() {
  return Kernel::Interrupts::getCurrentTask();
}
