#pragma once

#include "Ints.hpp"

#include "flo/Containers/Array.hpp"

#include "flo/Bitfields.hpp"

#define SYSREG(reg, type) \
struct reg##_S { \
  operator type() { type out; asm volatile("mov %%"#reg ", %0":"=r"(out)); return out; }\
  reg##_S &operator=(type value) { asm volatile("mov %0, %%"#reg:: "Nd"(value)); return *this; }\
  reg##_S &operator|=(type value) { return *this = static_cast<type>(*this) | value; }\
  reg##_S &operator&=(type value) { return *this = static_cast<type>(*this) & value; }\
}; inline reg##_S reg;

namespace flo {
  namespace CPU {
    inline void halt() {
      asm("hlt");
    }

    [[noreturn]] inline void hang() {
      while(1)
        halt();
      __builtin_unreachable();
    }

    SYSREG(cr0, uptr);
    SYSREG(cr2, uptr);
    SYSREG(cr3, uptr);
    SYSREG(cr4, uptr);

    namespace Impl {
      template<u32 regnum, typename type>
      struct MSR {
        operator type() {
          if constexpr(sizeof(type) == 4) {
            type out;
            asm volatile("rdmsr" : "=a"(out) : "c"(regnum));
            return out;
          }
          else if constexpr(sizeof(type) == 8) {
            type out1, out2;
            asm volatile("rdmsr" : "=a"(out1), "=d"(out2) : "c"(regnum));
            return (out1 & 0xFFFFFFFF) | ((out2 & 0xFFFFFFFF) << 32);
          }
        }

        MSR &operator=(type value) {
          if constexpr(sizeof(type) == 4)
            asm volatile("wrmsr" :: "a"(value), "c"(regnum));
          else if constexpr(sizeof(type) == 8)
            asm volatile("wrmsr" :: "a"(value), "d"(value >> 32), "c"(regnum));
          return *this;
        }
        MSR &operator|=(type value) { return *this = static_cast<type>(*this) | value; }
        MSR &operator&=(type value) { return *this = static_cast<type>(*this) & value; }
      };
    }

    inline Impl::MSR<0xC0000080, u32> IA32_EFER;
    inline Impl::MSR<0x0000001B, u64> IA32_APIC_BASE_MSR;
  }

  namespace Impl {
    //struct CPUIDOrderEaxEbxEcxEdx { u32 eax = 0, ebx = 0, ecx = 0, edx = 0; };
    struct CPUIDOrderEaxEbxEdxEcx { u32 eax = 0, ebx = 0, edx = 0, ecx = 0; };

    template<typename T>
    struct CPUID: T {
      T &v() { return static_cast<T &>(*this); }
      CPUID(): T() { // Empty 
      }
      CPUID(u32 func): T() {
        asm("cpuid" : "=a"(v().eax), "=b"(v().ebx), "=c"(v().ecx), "=d"(v().edx) : "a"(func));
      }
      CPUID(u32 func, u32 ecxArg): T() {
        asm("cpuid" : "=a"(v().eax), "=b"(v().ebx), "=c"(v().ecx), "=d"(v().edx) : "a"(func), "c"(ecxArg));
      }
    };

    template<typename T>
    T conditionalCPUID(u32 cpuidNum);

    template<typename T>
    T conditionalECPUID(u32 ecpuidNum);

    template<int startBit, int numBits>
    using CPUIDBits = flo::Bitfield<startBit, numBits, u32>;

    struct CPUIDData {
      CPUIDData()
        : cpuid0{0}
        , cpuid1{conditionalCPUID<decltype(cpuid1)>(1)}
      { }

      /* CPUID 0 */
      union {
        Impl::CPUID<Impl::CPUIDOrderEaxEbxEdxEcx> cpuid0;

        struct {
          u32 maxFunc{};
          flo::Array<char, 12> manufacturerID{};
          char manufIDTerminator = 0;
        };
      };

      /* CPUID 1 */
      union {
        Impl::CPUID<Impl::CPUIDOrderEaxEbxEdxEcx> cpuid1;
        struct {
          // Ugly registers. Leave be for now.
          u32 eax1;
          u32 ebx1;
          union {
            u32 edx1;
            CPUIDBits<0, 1> fpu;
            CPUIDBits<1, 1> virtual8086Extensions;
            CPUIDBits<2, 1> debuggingExtensions;
            CPUIDBits<3, 1> pageSizeExtension;
            CPUIDBits<4, 1> timeStampCounter;
            CPUIDBits<5, 1> modelSpecificRegisters;
            CPUIDBits<6, 1> physicalAddressExtension;
            CPUIDBits<7, 1> machineCheckException;
            CPUIDBits<8, 1> cmpxchg8;
            CPUIDBits<9, 1> apic;
            CPUIDBits<11, 1> systenterexit;
            CPUIDBits<12, 1> memoryTypeRanges;
            CPUIDBits<13, 1> pageGlobalEnable;
            CPUIDBits<14, 1> machineCheckArchitecture;
            CPUIDBits<15, 1> cmov;
            CPUIDBits<16, 1> pageAttributeTable;
            CPUIDBits<17, 1> pageSize36;
            CPUIDBits<18, 1> procSerialNum;
            CPUIDBits<19, 1> clflush;
            CPUIDBits<21, 1> debugStore;
            CPUIDBits<22, 1> thermalACPIRegs;
            CPUIDBits<23, 1> mmx;
            CPUIDBits<24, 1> fxsaverestore;
            CPUIDBits<25, 1> see;
            CPUIDBits<26, 1> see2;
            CPUIDBits<27, 1> selfSnoop;
            CPUIDBits<28, 1> hyperthreading;
            CPUIDBits<29, 1> thermalMonitorAutoLimit;
            CPUIDBits<30, 1> procIsIA64;
            CPUIDBits<31, 1> pendingBreakEnableWakeup;
          };
          union {
            u32 ecx1;
            CPUIDBits<0, 1> sse3;
            CPUIDBits<1, 1> pclmulqdq;
            CPUIDBits<2, 1> debugStore64;
            CPUIDBits<3, 1> monitorMWait;
            CPUIDBits<4, 1> cplQualifiedDebugStore;
            CPUIDBits<5, 1> virtualMachineExtensions;
            CPUIDBits<6, 1> saferModeExtensions;
            CPUIDBits<7, 1> enhancedSpeedStep;
            CPUIDBits<8, 1> thermalMonitor2;
            CPUIDBits<9, 1> ssse3;
            CPUIDBits<10, 1> contextID;
            CPUIDBits<11, 1> siliconDebugInterface;
            CPUIDBits<12, 1> fusedMultiplyAdd;
            CPUIDBits<13, 1> cmpxchg16b;
            CPUIDBits<14, 1> disableSendingTaskPriorityMessages;
            CPUIDBits<15, 1> perfmonAndDebug;
            CPUIDBits<17, 1> processContextIdentifiers;
            CPUIDBits<18, 1> directCacheAccess;
            CPUIDBits<19, 1> sse41;
            CPUIDBits<20, 1> sse42;
            CPUIDBits<21, 1> x2apic;
            CPUIDBits<22, 1> movbe;
            CPUIDBits<23, 1> popcnt;
            CPUIDBits<24, 1> tscDeadlineAPIC;
            CPUIDBits<25, 1> aes;
            CPUIDBits<26, 1> xsave;
            CPUIDBits<27, 1> osxsave;
            CPUIDBits<28, 1> avx;
            CPUIDBits<29, 1> f16;
            CPUIDBits<30, 1> rdrand;
            CPUIDBits<31, 1> hypervisor;
          };
        };
      };
    };
  }

  inline struct Impl::CPUIDData cpuid{};

  template<typename T>
  T Impl::conditionalCPUID(u32 cpuidNum) {
    if(cpuidNum <= cpuid.maxFunc)
      return T{cpuidNum};
    else
      return T{};
  }
}
