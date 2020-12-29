#include "flo/Mutex.hpp"

#include "flo/Multitasking.hpp"

void *flo::getCurrentThread();

namespace {
  bool tryLockWithThread(flo::Mutex &mtx, void *thread) {
    return mtx.flag.compareExchangeWeak(nullptr, thread);
  }
}

bool flo::Mutex::tryLock() {
  return tryLockWithThread(*this, flo::getCurrentThread());
}

bool flo::Mutex::isLocked() {
  return flag.load() != nullptr;
}

bool flo::Mutex::hasLock() {
  return flag.load() == flo::getCurrentThread();
}

void flo::Mutex::lock() {
  auto const curr = flo::getCurrentThread();
  while(!tryLockWithThread(*this, curr))
    flo::yield();
}

void flo::Mutex::unlock() {
  assert(hasLock());
  flag.store(nullptr);
}
