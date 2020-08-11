#pragma once

namespace flo {
  enum MemoryOrder {
    Relaxed                = __ATOMIC_RELAXED,
    Consume                = __ATOMIC_CONSUME,
    Acquire                = __ATOMIC_ACQUIRE,
    Release                = __ATOMIC_RELEASE,
    AcquireRelease         = __ATOMIC_ACQ_REL,
    SequentiallyConsistent = __ATOMIC_SEQ_CST,
  };

  template<typename T>
  struct Atomic {
    Atomic(T v): val{v} { }

    void store(T value, MemoryOrder order = MemoryOrder::Release) {
      return __atomic_store_n(&val, value, order);
    }

    T load(MemoryOrder order = MemoryOrder::Acquire) {
      return __atomic_load_n(&val, order);
    }

    bool compareExchangeWeak(T expected, T value) {
      return __atomic_compare_exchange_n(&val, &expected, value, true, MemoryOrder::Release, MemoryOrder::Relaxed);
    }

    bool compareExchangeStrong(T expected, T value) {
      return __atomic_compare_exchange_n(&val, &expected, value, false, MemoryOrder::Release, MemoryOrder::Relaxed);
    }

    T val;
  };
}
