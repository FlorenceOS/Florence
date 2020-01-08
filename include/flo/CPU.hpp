#include "Ints.hpp"

#define SYSREG(reg, type) \
struct reg##_S { \
  operator type() { type out; asm("mov %%"#reg", %0":"=r"(out)); return out; }\
  reg##_S &operator=(type value) { asm("mov %0, %%"#reg :: "Nd"(value)); return *this; }\
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
