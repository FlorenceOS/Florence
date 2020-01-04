#pragma once

#include "Ints.hpp"

namespace flo {
  template<typename T>
  struct RandomDevice {
    using result_type = T;
    static_assert(std::is_integral_v<T>);
    static constexpr result_type min() { return std::numeric_limits<T>::min(); }
    static constexpr result_type max() { return std::numeric_limits<T>::max(); }

    template<typename TyRes = result_type>
    [[nodiscard]]
    static TyRes get() {
      if constexpr(sizeof(TyRes) > sizeof(result_type)) {
        // We combine the results of more randomizations
        std::array<u8, sizeof(result_type)> result;
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
}
