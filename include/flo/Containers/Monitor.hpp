#pragma once

#include "flo/Mutex.hpp"

namespace flo {
  template<typename T>
  struct Monitored {
    template<typename Func>
    void operator()(Func &&f) {
      flo::LockGuard<flo::Mutex> lock{m};
      f(value);
    }
  private:
    T value;
    flo::Mutex m;
  };
}
