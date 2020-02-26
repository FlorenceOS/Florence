#pragma once

#include "flo/GenAssignmentOps.hpp"

namespace flo {
  template<typename Tag, typename ValueT>
  struct StrongTypedef: GenAssignmentOps<StrongTypedef<Tag, ValueT>, ValueT> {
    template<typename T = ValueT>
    constexpr T get() const { return T{val}; }

    // Conversions to are explicit
    constexpr explicit StrongTypedef() = default;
    constexpr explicit StrongTypedef(ValueT val_) : val{val_} { }

    // Conversions from are implicit
    constexpr operator bool() const { return val != 0; }
    constexpr operator ValueT() const { return val; }
    constexpr ValueT operator()() const { return val; }

    // Comparisons
    constexpr bool operator==(StrongTypedef const &other) const { return val == other(); }
    constexpr bool operator!=(StrongTypedef const &other) const { return val != other(); }
    constexpr bool operator< (StrongTypedef const &other) const { return val <  other(); }
    constexpr bool operator> (StrongTypedef const &other) const { return val >  other(); }
    constexpr bool operator<=(StrongTypedef const &other) const { return val <= other(); }
    constexpr bool operator>=(StrongTypedef const &other) const { return val >= other(); }
    //constexpr bool operator!=(std::nullptr_t) const { return static_cast<bool>(*this); }
    //constexpr bool operator==(std::nullptr_t) const { return !(*this != nullptr); }

    // Arithmetics
    constexpr auto operator<<(ValueT const &other) const { return Tag{StrongTypedef{val << other}}; }
    constexpr auto operator>>(ValueT const &other) const { return Tag{StrongTypedef{val >> other}}; }

    constexpr auto operator| (StrongTypedef const &other) const { return Tag{StrongTypedef{val |  other()}}; }
    constexpr auto operator& (StrongTypedef const &other) const { return Tag{StrongTypedef{val &  other()}}; }

    constexpr auto operator+ (StrongTypedef const &other) const { return Tag{StrongTypedef{val +  other()}}; }
    constexpr auto operator- (StrongTypedef const &other) const { return Tag{StrongTypedef{val -  other()}}; }

    constexpr auto operator% (StrongTypedef const &other) const { return Tag{StrongTypedef{val %  other()}}; }
    constexpr auto operator/ (StrongTypedef const &other) const { return Tag{StrongTypedef{val /  other()}}; }

    // Unary ops
    constexpr auto operator~() const { return Tag{StrongTypedef{~val}}; }
    constexpr auto operator-() const { return Tag{StrongTypedef{-val}}; }
  private:
    ValueT val;
  };
}

#define FLO_STRONG_TYPEDEF(type, underlying) \
struct type: flo::StrongTypedef<type, underlying> { using flo::StrongTypedef<type, underlying>::StrongTypedef; };
