#include "Ints.hpp"

#include "flo/Random.hpp"
#include "flo/IO.hpp"
#include "flo/CPU.hpp"

extern "C" int memcmp(const void *lhs, const void *rhs, uSz num) {
  auto ul = reinterpret_cast<u8 const *>(lhs);
  auto ur = reinterpret_cast<u8 const *>(rhs);

  while(num--) {
    int a = *ul++ - *ur++;
    if(a)
      return a;
  }
  return 0;
}

namespace {
  struct {
    u64 a = 0x69FF1337ABCDEFAAULL;
    u64 b = 0x420B16D1CCABC123ULL;
  } simpleRandState;

  u64 simpleRand() {
    auto t = simpleRandState.a;
    auto const s = simpleRandState.b;
    simpleRandState.a = s;
    t ^= t << 23;
    t ^= t >> 17;
    t ^= s ^ (s >> 26);
    simpleRandState.b = t;
    return t + s;
  }

  bool const RDRANDSupported = flo::CPUID::cpuid1.rdrand;
}

using Constructor = void(*)();
extern "C" Constructor constructorsStart;
extern "C" Constructor constructorsEnd;

extern "C" void callGlobalConstructors() {
  for(auto c = &constructorsStart; c < &constructorsEnd; ++ c)
    (**c)();
}

u64 flo::getRand() {
  if(RDRANDSupported)
    return flo::randomNative.get<u64>();
  else
    return simpleRand();
}

extern "C" void atexit() { }
extern "C" void __cxa_guard_acquire() { }
extern "C" void __cxa_guard_release() { }
