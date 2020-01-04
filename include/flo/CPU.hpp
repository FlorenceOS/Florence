#include "Ints.hpp"

namespace flo {
  namespace CPU {
    inline void halt() {
      asm("hlt");
    }

    [[noreturn]] inline void hang() {
      while(1) halt();
    }
  }
}
