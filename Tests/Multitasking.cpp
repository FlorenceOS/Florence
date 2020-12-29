#include "flo/Mutex.hpp"

#include "Testing.hpp"

#include "pthread.h"

void flo::yield() {
  pthread_yield();
}

void *flo::getCurrentThread() {
  return (void *)(uptr)gettid();
}
