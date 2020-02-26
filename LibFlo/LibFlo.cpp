using Constructor = void(*)();
extern "C" Constructor constructorsStart;
extern "C" Constructor constructorsEnd;

extern "C" void callGlobalConstructors() {
  for(auto c = &constructorsStart; c < &constructorsEnd; ++c)
    (**c)();
}

extern "C" void __cxa_guard_acquire() { }
extern "C" void __cxa_guard_release() { }
