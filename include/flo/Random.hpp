#pragma once

#include "Ints.hpp"
#include "flo/TypeTraits.hpp"
#include "flo/Limits.hpp"
#include "flo/Util.hpp"

namespace flo {
  template<typename T>
  struct RandomDevice {
    using result_type = T;
    static_assert(isIntegral<T>);
    static constexpr result_type min() { return Limits<T>::min(); }
    static constexpr result_type max() { return Limits<T>::max(); }

    template<typename DesiredType = result_type>
    [[nodiscard]]
    static DesiredType get() {
      if constexpr(sizeof(DesiredType) > sizeof(result_type)) {
        // We combine the results of more randomizations
        Array<u8, sizeof(DesiredType)> result;
        auto it = result.begin();
        while(it != result.end()) {
          *reinterpret_cast<result_type *>(&*it) = get();
          it += sizeof(result_type);
        }
        return *reinterpret_cast<DesiredType *>(result.data());
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
  template<typename T>
  struct UniformInts {
    static_assert(isIntegral<T>);
    constexpr UniformInts(T min, T max) {
      this->set(min, max);
    }

    constexpr void set(T min, T max) {
      this->min = min;
      this->max = max;
      update();
    }

    template<typename BitSource>
    T operator()(BitSource &bitSource) const {
      // We only support u64 bit sources for now
      static_assert(BitSource::min() == flo::Limits<u64>::min);
      static_assert(BitSource::max() == flo::Limits<u64>::max);

      while(1) if(auto val = bitSource() & bitmask; val <= max - min)
        return val + min;
    }

  private:
    /* Must set bitmask */
    constexpr void update() {
      // Special case where entire range of type is specified, we can't do max - min + 1 since it will overflow
      if(min == flo::Limits<T>::min && max == flo::Limits<T>::max)
        bitmask = ~T{0};
      else {
        auto desiredRange = max - min + 1;
        auto desiredBits = flo::Limits<T>::bits - flo::Util::countHighZeroes(desiredRange);

        if(desiredBits == flo::Limits<T>::bits)
          bitmask = ~T{0};
        else
          bitmask = (T{1} << desiredBits) - 1;
      }
    }

    T bitmask;
    T min;
    T max;
  };
}
