#pragma once

#include "flo/Containers/Atomic.hpp"
#include "flo/Multitasking.hpp"

namespace flo {
  struct Mutex {
    bool tryLock();
    bool isLocked();
    bool hasLock();
    void lock();
    void unlock();
    flo::Atomic<threadID> flag = nullptr;
  };

  enum struct LockMode {
    Lock,
    AlreadyLocked,
  };

  template<typename T = Mutex>
  struct LockGuard {
    LockGuard(T &l, LockMode mode = LockMode::Lock): lockable{l} {
      if(mode == LockMode::Lock)
        lockable.lock();
    }

    void unlock() {
      lockable.unlock();
    }

    ~LockGuard() {
      if(lockable.isLocked())
        lockable.unlock();
    }

  private:
    T &lockable;
  };
}
