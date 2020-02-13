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
        operator type() { type out; asm volatile("rdmsr" : "=a"(out) : "c"(regnum)); return out; }
        MSR &operator=(type value) { asm volatile("wrmsr" :: "a"(value), "c"(regnum)); return *this; }
        MSR &operator|=(type value) { return *this = static_cast<type>(*this) | value; }
        MSR &operator&=(type value) { return *this = static_cast<type>(*this) & value; }
      };
    }

    inline Impl::MSR<0xC0000080, u32> IA32_EFER;
  }

  namespace CPUID {
    namespace Impl {
      // For when we don't have a type for the CPUID leaf yet
      struct Plain { u32 eax = 0, ebx = 0, ecx = 0, edx = 0; };

      template<typename T = Plain>
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

      template<int startBit, int numBits>
      using CPUIDBits = flo::Bitfield<startBit, numBits, u32>;

      struct CPUID0 {
        // Should always exist, no need to init anything
        union {
          u32 eax;
          u32 maxFunc;
        };

        union {
          struct {
            u32 ebx;
            u32 edx;
            u32 ecx;
          };
          struct {
            flo::Array<char, 12> manufacturerID;
          };
        };
      };
    }

    // CPUID funcs
    auto const inline cpuid0 = Impl::CPUID<Impl::CPUID0>(0);

    auto const inline __attribute__((pure)) getMaxFunc()        { return cpuid0.maxFunc; }
    auto const inline __attribute__((pure)) getManufacturerID() { return cpuid0.manufacturerID; }
    auto const inline __attribute__((pure)) hasFunc(u32 func)   { return getMaxFunc() <= func; }

    namespace Impl {
      struct CPUID1 {
        CPUID1() { eax = ebx = ecx = edx = 0; }
        // Ugly registers. Leave be for now.
        u32 eax;
        u32 ebx;
        union {
          u32 ecx;

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
          u32 edx;

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
    }

    auto const inline cpuid1  = hasFunc(1) ? Impl::CPUID<Impl::CPUID1>(1)    : Impl::CPUID<Impl::CPUID1>();
    auto const inline cpuid2  = hasFunc(2) ? Impl::CPUID(2)    : Impl::CPUID();
    auto const inline cpuid3  = hasFunc(3) ? Impl::CPUID(3)    : Impl::CPUID();
    auto const inline cpuid4  = hasFunc(4) ? Impl::CPUID(4)    : Impl::CPUID();
    auto const inline cpuid70 = hasFunc(7) ? Impl::CPUID(7, 0) : Impl::CPUID();
    auto const inline cpuid71 = hasFunc(7) ? Impl::CPUID(7, 1) : Impl::CPUID();

      // CPUID efuncs
    auto const inline cpuide0 = Impl::CPUID(0x80000000);

    auto inline __attribute__((pure)) getMaxEFunc()      { return cpuide0.eax - 0x80000000; }
    auto inline __attribute__((pure)) hasEFunc(u32 func) { return getMaxEFunc() <= func; }

    auto const inline cpuide1 = hasEFunc(1) ? Impl::CPUID(0x80000001) : Impl::CPUID();
    auto const inline cpuide2 = hasEFunc(2) ? Impl::CPUID(0x80000002) : Impl::CPUID();
    auto const inline cpuide3 = hasEFunc(3) ? Impl::CPUID(0x80000003) : Impl::CPUID();
    auto const inline cpuide4 = hasEFunc(4) ? Impl::CPUID(0x80000004) : Impl::CPUID();
    auto const inline cpuide5 = hasEFunc(5) ? Impl::CPUID(0x80000005) : Impl::CPUID();
    auto const inline cpuide6 = hasEFunc(6) ? Impl::CPUID(0x80000006) : Impl::CPUID();
    auto const inline cpuide7 = hasEFunc(7) ? Impl::CPUID(0x80000007) : Impl::CPUID();
    auto const inline cpuide8 = hasEFunc(8) ? Impl::CPUID(0x80000008) : Impl::CPUID();
  }
}
