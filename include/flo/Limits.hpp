#pragma once

#include "Ints.hpp"

#include "flo/TypeTraits.hpp"

namespace flo {
  template<typename T>
  struct Limits {
    template<int base>
    static constexpr uSz calcDigits() {
      auto val = max;
      uSz result = 0;
      do {
        val /= base;
        ++result;
      } while(val);
      return result;
    }

    constexpr static uSz digits2 = sizeof(T) * 8;
    constexpr static uSz digits10 = calcDigits<10>();
    constexpr static uSz digits16 = sizeof(T) * 2;

    constexpr static uSz bits = digits2;
    constexpr static uSz bytes = sizeof(T);
    constexpr static uSz nibbles = digits16;

    template<int base>
    constexpr static uSz digitsBase = calcDigits<base>();

    static constexpr T calcSignedMax() {
      T result = 0;
      for(int i = 0; i < bits - 1; ++i) // Set all bits but the highests one (sign)
        result |= (T{1} << i);
      return result;
    }

    constexpr static T min = isSigned<T> ? (T{1} << (digits2 - 1)) : 0;
    constexpr static T max = isSigned<T> ? calcSignedMax() : ~T{0};
  };

  static_assert(Limits<signed int>::min == -2'147'483'648);
  static_assert(Limits<signed int>::max ==  2'147'483'647);
  static_assert(Limits<unsigned int>::min == 0u);
  static_assert(Limits<unsigned int>::max == 0xFFFFFFFFu);
}
