#pragma once

#include "flo/GenAssignmentOps.hpp"

namespace flo {
  template<typename Tag, typename ValueT>
  struct StrongTypedef: GenAssignmentOps<StrongTypedef<Tag, ValueT>, ValueT> {
    template<typename T = ValueT>
    constexpr T get() const { return T{val}; }

    // Conversions to are explicit
    constexpr explicit __attribute__((always_inline)) StrongTypedef() = default;
    constexpr explicit __attribute__((always_inline)) StrongTypedef(ValueT val_) : val{val_} { }

    // Conversions from are implicit
    constexpr __attribute__((always_inline)) operator bool() const { return val != 0; }
    constexpr __attribute__((always_inline)) operator ValueT() const { return val; }
    constexpr __attribute__((always_inline)) ValueT operator()() const { return val; }

    // Comparisons
    constexpr __attribute__((always_inline)) bool operator==(StrongTypedef const &other) const { return val == other(); }
    constexpr __attribute__((always_inline)) bool operator!=(StrongTypedef const &other) const { return val != other(); }
    constexpr __attribute__((always_inline)) bool operator< (StrongTypedef const &other) const { return val <  other(); }
    constexpr __attribute__((always_inline)) bool operator> (StrongTypedef const &other) const { return val >  other(); }
    constexpr __attribute__((always_inline)) bool operator<=(StrongTypedef const &other) const { return val <= other(); }
    constexpr __attribute__((always_inline)) bool operator>=(StrongTypedef const &other) const { return val >= other(); }

    // Arithmetics
    constexpr __attribute__((always_inline)) auto operator<<(ValueT const &other) const { return Tag{StrongTypedef{val << other}}; }
    constexpr __attribute__((always_inline)) auto operator>>(ValueT const &other) const { return Tag{StrongTypedef{val >> other}}; }

    constexpr __attribute__((always_inline)) auto operator| (StrongTypedef const &other) const { return Tag{StrongTypedef{val |  other()}}; }
    constexpr __attribute__((always_inline)) auto operator& (StrongTypedef const &other) const { return Tag{StrongTypedef{val &  other()}}; }

    constexpr __attribute__((always_inline)) auto operator+ (StrongTypedef const &other) const { return Tag{StrongTypedef{val +  other()}}; }
    constexpr __attribute__((always_inline)) auto operator- (StrongTypedef const &other) const { return Tag{StrongTypedef{val -  other()}}; }

    constexpr __attribute__((always_inline)) auto operator% (StrongTypedef const &other) const { return Tag{StrongTypedef{val %  other()}}; }
    constexpr __attribute__((always_inline)) auto operator/ (StrongTypedef const &other) const { return Tag{StrongTypedef{val /  other()}}; }

    // Unary ops
    constexpr __attribute__((always_inline)) auto operator~() const { return Tag{StrongTypedef{~val}}; }
    constexpr __attribute__((always_inline)) auto operator-() const { return Tag{StrongTypedef{-val}}; }
  private:
    ValueT val;
  };
}

#define FLO_STRONG_TYPEDEF(type, underlying) \
struct type: flo::StrongTypedef<type, underlying> { using flo::StrongTypedef<type, underlying>::StrongTypedef; };
