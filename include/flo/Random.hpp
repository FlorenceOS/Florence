#pragma once

#include "Ints.hpp"
#include "flo/TypeTraits.hpp"
#include "flo/Limits.hpp"

namespace flo {
  template<typename T>
  struct RandomDevice {
    using result_type = T;
    static_assert(isIntegral<T>);
    static constexpr result_type min() { return Limits<T>::min(); }
    static constexpr result_type max() { return Limits<T>::max(); }

    template<typename DesiredType = result_type>
    [[nodiscard]]
    static TyRes get() {
      if constexpr(sizeof(TyRes) > sizeof(result_type)) {
        // We combine the results of more randomizations
        Array<u8, sizeof(DesiredType)> result;
        auto it = result.begin();
        while(it != result.end()) {
          *reinterpret_cast<result_type>(&*it) = get();
          it += sizeof(result_type);
        }
        return *reinterpret_cast<TyRes *>(result.data());
      }
      else {
        // Just a simple randomization
        result_type retval;
        asm volatile("1:rdrand %0\njnc 1b\n":"=r"(retval));
        return retval;
      }
    }

    [[nodiscard]]
    auto operator()() {
      return get();
    }
  };

  inline RandomDevice<u64> random64;
  inline RandomDevice<u32> random32;
  inline flo::conditional<sizeof(void *) == 4, RandomDevice<u32>, RandomDevice<u64>> randomNative;

  u64 getRand();
}
