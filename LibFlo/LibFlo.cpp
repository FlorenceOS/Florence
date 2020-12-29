#include "Ints.hpp"

// Detect freestanding
#if defined __has_include
#if !__has_include (<stdio.h>)

using Constructor = void(*)();
extern "C" Constructor constructorsStart;
extern "C" Constructor constructorsEnd;

extern "C" void callGlobalConstructors() {
  for(auto c = &constructorsStart; c < &constructorsEnd; ++c)
    (**c)();
}

extern "C" void __cxa_guard_acquire() { }
extern "C" void __cxa_guard_release() { }

extern "C" void *memcpy(void *destination, void const *source, uSz num) {
  auto src = (u8 const *)source;
  auto dest = (u8 *)destination;

  for(; num; --num)
    *dest++ = *src++;

  return destination;
}

#endif
#endif
