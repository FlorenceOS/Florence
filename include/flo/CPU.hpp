#pragma once

#include "Ints.hpp"
#include "flo/Containers/Array.hpp"
#include "flo/Bitfields.hpp"

#define SYSREG(reg, type) \
struct reg##_S { \
  operator type() { type out; asm volatile("mov %0, %%"#reg:"=r"(out)); return out; }\
  reg##_S &operator=(type value) { asm volatile("mov %%"#reg ", %0":: "Nd"(value)); return *this; }\
  reg##_S &operator|=(type value) { return *this = static_cast<type>(*this) | value; }\
  reg##_S &operator&=(type value) { return *this = static_cast<type>(*this) & value; }\
} reg;

namespace flo {
  namespace CPU {
    inline void halt() {
      asm("hlt");
    }

    [[noreturn]] inline void hang() {
      while(1)
        halt();
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

    Impl::MSR<0xC0000080, u32> IA32_EFER;
  }

  namespace CPUID {
    namespace Impl {
      struct CPUID {
        CPUID(u32 func) {
          asm("cpuid" : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx) : "a"(func));
        }
        u32 eax;
        u32 ebx;
        u32 ecx;
        u32 edx;
      };
    }

    struct VendorString {
      VendorString() {
        Impl::CPUID c(0);
        ebx = c.ebx;
        ecx = c.ecx;
        edx = c.edx;
      }

      union {
        struct {
          u32 ebx;
          u32 edx;
          u32 ecx;
        };
        std::array<char, 12> chars;
      };
    };

    u32 inline maxFunc = []() {
      Impl::CPUID c(0x80000000);
      return c.eax;
    }();
  }
}
