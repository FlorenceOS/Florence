#pragma once

#include "Ints.hpp"

namespace flo {
  template<unsigned startBit_, unsigned numBits_, typename Container_ = u64>
  struct Bitfield {
  private:
    constexpr static auto mask() {
      Container out{};
      for(unsigned i = startBit; i < startBit + numBits; ++ i) {
        out |= Container{1} << i;
      }
      return out;
    }

  public:
    constexpr Bitfield() = default;
    constexpr Bitfield(Container_ val) { *this = val; }
    
    static constexpr auto startBit = startBit_, numBits = numBits_;
    using Container = Container_;
    static constexpr auto selfMask = mask();
    static constexpr auto otherMask = ~selfMask;

    static_assert(startBit + numBits <= sizeof(Container) * 8);

    constexpr operator Container() const {
      return (*reinterpret_cast<Container const *>(this) & selfMask) >> startBit;
    }

    constexpr auto operator=(Container val) {
      return *reinterpret_cast<Container*>(this) =
            (*reinterpret_cast<Container*>(this) & otherMask) | ((val << startBit) & selfMask);
    }

    constexpr Bitfield &operator+= (Container_ val) { return *this = *this + val; }
    constexpr Bitfield &operator-= (Container_ val) { return *this = *this - val; }
    constexpr Bitfield &operator*= (Container_ val) { return *this = *this * val; }
    constexpr Bitfield &operator/= (Container_ val) { return *this = *this / val; }
    constexpr Bitfield &operator%= (Container_ val) { return *this = *this % val; }
    constexpr Bitfield &operator^= (Container_ val) { return *this = *this ^ val; }
    constexpr Bitfield &operator&= (Container_ val) { return *this = *this & val; }
    constexpr Bitfield &operator|= (Container_ val) { return *this = *this | val; }
    constexpr Bitfield &operator>>=(Container_ val) { return *this = *this >> val; }
    constexpr Bitfield &operator<<=(Container_ val) { return *this = *this << val; }
    constexpr Bitfield &operator++ ()               { return *this = *this + 1; }
    constexpr Container operator++ (int)            { Container save = *this; ++(*this); return save; }
    constexpr Bitfield &operator-- ()               { return *this = *this - 1; }
    constexpr Container operator-- (int)            { Container save = *this; --(*this); return save; }

    constexpr Container operator()() const { return Container{*this}; }
  };
}