#pragma once

namespace flo {
  template<typename T1, typename T2>
  struct Pair {
    T1 first;
    T2 second;
  };

  template<typename T1, typename T2>
  Pair(T1, T2) -> Pair<T1, T2>;

  template<typename T>
  using Two = Pair<T, T>;
}
