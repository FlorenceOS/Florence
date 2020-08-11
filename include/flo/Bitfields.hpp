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
        out |= nvContainer{1} << i;
      }
      return out;
    }

  public:
    using Container = Container_;

    constexpr __attribute__((always_inline)) Bitfield() = default;
    constexpr __attribute__((always_inline)) Bitfield(nvContainer val) { *this = val; }

    static constexpr auto startBit  = startBit_, numBits = numBits_;
    static constexpr auto selfMask  = mask();
    static constexpr auto otherMask = ~selfMask;

    static_assert(startBit + numBits <= sizeof(nvContainer) * 8);

    constexpr __attribute__((always_inline)) operator nvContainer() const {
      return (data & selfMask) >> startBit;
    }

    constexpr __attribute__((always_inline)) operator nvContainer() const volatile {
      return (data & selfMask) >> startBit;
    }

    constexpr __attribute__((always_inline)) auto &operator=(nvContainer val) {
      data = (data & otherMask) | ((val << startBit) & selfMask);
      return *this;
    }

    constexpr __attribute__((always_inline)) auto &operator=(nvContainer val) volatile {
      data = (data & otherMask) | ((val << startBit) & selfMask);
      return *this;
    }

    constexpr __attribute__((always_inline)) Bitfield &operator+= (nvContainer val) { return *this = *this + val; }
    constexpr __attribute__((always_inline)) Bitfield &operator-= (nvContainer val) { return *this = *this - val; }
    constexpr __attribute__((always_inline)) Bitfield &operator*= (nvContainer val) { return *this = *this * val; }
    constexpr __attribute__((always_inline)) Bitfield &operator/= (nvContainer val) { return *this = *this / val; }
    constexpr __attribute__((always_inline)) Bitfield &operator%= (nvContainer val) { return *this = *this % val; }
    constexpr __attribute__((always_inline)) Bitfield &operator^= (nvContainer val) { return *this = *this ^ val; }
    constexpr __attribute__((always_inline)) Bitfield &operator&= (nvContainer val) { return *this = *this & val; }
    constexpr __attribute__((always_inline)) Bitfield &operator|= (nvContainer val) { return *this = *this | val; }
    constexpr __attribute__((always_inline)) Bitfield &operator>>=(nvContainer val) { return *this = *this >> val; }
    constexpr __attribute__((always_inline)) Bitfield &operator<<=(nvContainer val) { return *this = *this << val; }
    constexpr __attribute__((always_inline)) Bitfield &operator++ ()                { return *this = *this + 1; }
    constexpr __attribute__((always_inline)) nvContainer operator++ (int)           { nvContainer save = *this; ++(*this); return save; }
    constexpr __attribute__((always_inline)) Bitfield &operator-- ()                { return *this = *this - 1; }
    constexpr __attribute__((always_inline)) nvContainer operator-- (int)           { nvContainer save = *this; --(*this); return save; }

    constexpr __attribute__((always_inline)) nvContainer operator()() const { return nvContainer{*this}; }

    Container data;
  };
}