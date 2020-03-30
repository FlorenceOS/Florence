#pragma once

#include "Ints.hpp"

#include "flo/TypeTraits.hpp"

namespace flo {
  template<unsigned startBit_, unsigned numBits_, typename Container_ = u64>
  struct Bitfield {
  private:
    using nvContainer = flo::removeCV<Container_>;
    constexpr static auto mask() {
      nvContainer out{};
      for(unsigned i = startBit; i < startBit + numBits; ++i) {
        out |= Container{1} << i;
      }
      return out;
    }

  public:
    using Container = Container_;

    constexpr Bitfield() = default;
    constexpr Bitfield(nvContainer val) { *this = val; }

    static constexpr auto startBit  = startBit_, numBits = numBits_;
    static constexpr auto selfMask  = mask();
    static constexpr auto otherMask = ~selfMask;

    static_assert(startBit + numBits <= sizeof(Container) * 8);

    constexpr operator nvContainer() const {
      return (*reinterpret_cast<nvContainer const *>(this) & selfMask) >> startBit;
    }

    constexpr operator nvContainer() const volatile {
      return (*reinterpret_cast<nvContainer const volatile *>(this) & selfMask) >> startBit;
    }

    constexpr auto operator=(Container val) {
      return *reinterpret_cast<nvContainer *>(this) =
            (*reinterpret_cast<nvContainer *>(this) & otherMask) | ((val << startBit) & selfMask);
    }

    constexpr auto operator=(Container val) volatile {
      return *reinterpret_cast<nvContainer volatile *>(this) =
            (*reinterpret_cast<nvContainer volatile *>(this) & otherMask) | ((val << startBit) & selfMask);
    }

    constexpr Bitfield &operator+= (nvContainer val) { return *this = *this + val; }
    constexpr Bitfield &operator-= (nvContainer val) { return *this = *this - val; }
    constexpr Bitfield &operator*= (nvContainer val) { return *this = *this * val; }
    constexpr Bitfield &operator/= (nvContainer val) { return *this = *this / val; }
    constexpr Bitfield &operator%= (nvContainer val) { return *this = *this % val; }
    constexpr Bitfield &operator^= (nvContainer val) { return *this = *this ^ val; }
    constexpr Bitfield &operator&= (nvContainer val) { return *this = *this & val; }
    constexpr Bitfield &operator|= (nvContainer val) { return *this = *this | val; }
    constexpr Bitfield &operator>>=(nvContainer val) { return *this = *this >> val; }
    constexpr Bitfield &operator<<=(nvContainer val) { return *this = *this << val; }
    constexpr Bitfield &operator++ ()               { return *this = *this + 1; }
    constexpr Container operator++ (int)            { Container save = *this; ++(*this); return save; }
    constexpr Bitfield &operator-- ()               { return *this = *this - 1; }
    constexpr Container operator-- (int)            { Container save = *this; --(*this); return save; }

    constexpr Container operator()() const { return Container{*this}; }
  };
}