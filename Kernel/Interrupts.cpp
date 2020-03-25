#include "flo/Assert.hpp"
#include "flo/Bitfields.hpp"
#include "flo/Interrupts.hpp"
#include "flo/IO.hpp"
#include "flo/Kernel.hpp"
#include "flo/Memory.hpp"

extern "C" void *exceptionHandlers[0x20];
extern "C" void *irqHandlers[0x10];
extern "C" void *schedulerCalls[0x2];

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
      case Breakpoint:
      case Overflow:
      case BoundRangeExceeded:
      case DeviceNotAvailable:
      case x87FloatingPointException:
      case AlignmentCheck:
      case SIMDFloatingPointException:
        return false;
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

    void dumpFrame(flo::Interrupts::ErrorFrame *frame) {
      flo::Interrupts::pline("RAX=", frame->rax, " RBX=", frame->rbx, " RCX=", frame->rcx, " RDX=", frame->rdx);
      flo::Interrupts::pline("RSI=", frame->rsi, " RDI=", frame->rdi, " RBP=", frame->rbp, " RSP=", frame->rsp);
      flo::Interrupts::pline("R8 =", frame->r8 , " R9 =", frame->r9 , " R10=", frame->r10, " R11=", frame->r11);
      flo::Interrupts::pline("R12=", frame->r12, " R13=", frame->r13, " R14=", frame->r14, " R15=", frame->r15);
      flo::Interrupts::pline("SS =", frame->ss , " CS =", frame->cs,  " RIP=", frame->rip, " EC =", frame->errorCode);
    }

    void exceptionHandler(flo::Interrupts::ErrorFrame *frame) {
      flo::Interrupts::pline("CPU exception ", frame->interruptNumber, " (",
        flo::Interrupts::exceptionToString(frame->interruptNumber), ") at DIP=", flo::deslide(frame->rip));
      flo::Interrupts::pline("In function ", flo::symbolName(frame->rip));
      dumpFrame(frame);

      if(flo::Interrupts::isFatal(frame->interruptNumber))
        assert_not_reached();
      else
        flo::printBacktrace();
    }

    struct Task {
      ErrorFrame ef;
      Task *next = nullptr;
      flo::Function<void(TaskControlBlock &)> callable;

      flo::TaskControlBlock controlBlock;


      Task(char const *name) {
        flo::Util::setmem((u8 *)&ef, 0, sizeof(ef));
        controlBlock.name = name;
      }

      ~Task() {
        freeStack((void *)ef.rbp);
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
      flo::Interrupts::pline("Task ", getCurrentTask()->controlBlock.name, " returned, killing.");
      flo::exit();
    }

    void waitForInterrupt() {
      asm("sti\nhlt\ncli");
    }

    void doYieldImpl(flo::Interrupts::ErrorFrame *frame) {
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

    void doKillTask(flo::Interrupts::ErrorFrame *frame) {
      while(!taskQueue.peek()) // No other task to execute
        waitForInterrupt();

      auto task = getCurrentTask();

      task->~Task();
      flo::Allocator<Task>::deallocate(task);

      task = taskQueue.getAndPop();

      setCurrentTask(task);

      task->restoreRegs(frame);
      return;      
    }

    flo::Array<flo::Function<void()>, 0x10> registeredHandlerFuncs;

    void doEOI() {
      pline("FIXME: EOI");
    }
  }
}

extern "C" void interruptHandler() {
  flo::Interrupts::ErrorFrame *frame;
  __asm__(
    "lea 16(%%rbp), %0\n"
    : "=r"(frame)
  );

  switch(frame->interruptNumber) {
  case 0x00 ... 0x1F:
    flo::Interrupts::exceptionHandler(frame);
    break;

  case 0x30:
    return flo::Interrupts::doYieldImpl(frame);

  case 0x31:
    return flo::Interrupts::doKillTask(frame);

  case 0x20 ... 0x2F:
    {
      auto &handler = flo::Interrupts::registeredHandlerFuncs[frame->interruptNumber - 0x20];
      if(handler)
        return handler();
      flo::Interrupts::doEOI();
    }

    [[fallthrough]];
  default:
    flo::Interrupts::pline("Unhandled IRQ ", frame->interruptNumber, "!!");
    assert_not_reached();
    break;
  }
}

void flo::Interrupts::initialize() {
  flo::Interrupts::idt = flo::Allocator<flo::Interrupts::IDT>::allocate();

  // CPU exceptions
  flo::Interrupts::IDTEntry::Attrib attributes;
  attributes.gateType = 0xf;
  attributes.storage = 0;
  attributes.privLevel = 0;
  attributes.present = 1;

  uSz i = 0;
  for(uSz j = 0; j < flo::Util::arrSz(exceptionHandlers); ++j, ++i)
    flo::Interrupts::idt->entries[i] = flo::Interrupts::encode(exceptionHandlers[j], attributes);

  // IRQs
  attributes.gateType = 0xE;

  for(uSz j = 0; j < flo::Util::arrSz(irqHandlers); ++j, ++i)
    flo::Interrupts::idt->entries[i] = flo::Interrupts::encode(irqHandlers[j], attributes);

  // Software yield
  for(uSz j = 0; j < 0x10; ++j, ++i)
    if(j < flo::Util::arrSz(schedulerCalls))
      flo::Interrupts::idt->entries[i] = flo::Interrupts::encode(schedulerCalls[j], attributes);

  auto mainTask = flo::Allocator<flo::Interrupts::Task>::allocate();
  new (mainTask) Task{"Main task"};
  mainTask->controlBlock.isRunnable = true;
  setCurrentTask(mainTask);

  // Enable interrupts
  struct {
    u16 limit = sizeof(flo::Interrupts::IDT) - 1;
    u64 base = (u64)flo::Interrupts::idt;
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
  auto task = flo::Allocator<flo::Interrupts::Task>::allocate();
  new (task) flo::Interrupts::Task{taskName};
  task->callable = flo::move(func);
  task->ef.rip = (uptr)&flo::Interrupts::taskEntry;
  task->ef.rbp = task->ef.rsp = (uptr)makeStack();
  task->ef.ss = 0x10;
  task->ef.cs = 0x08;
  flo::Interrupts::taskQueue.insertBack(task);

  return task->controlBlock;
}
