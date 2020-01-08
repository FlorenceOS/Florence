#pragma once

#include <limits>
#include <utility>

namespace flo {
  enum struct IterationDecision {
    keepGoing,
    stop,
  };

  namespace Util {
    template<typename T>
    auto constexpr binDigits = std::numeric_limits<T>::digits;

    template<typename T, typename F>
    constexpr void forEachBitLowToHigh(T num, F &&functor) {
      for(int bitnum = 0; bitnum < binDigits<T>; ++ bitnum) {
        IterationDecision decision = functor((num >> bitnum) & 1, bitnum);
        if(decision == IterationDecision::stop)
          break;
      }
    }

    template<typename T, typename F>
    constexpr void forEachBitHighToLow(T num, F &&functor) {
      for(int bitnum = binDigits<T>; bitnum --> 0;) {
        IterationDecision decision = functor((num >> bitnum) & 1, bitnum);
        if(decision == IterationDecision::stop)
          break;
      }
    }

    template<typename T>
    [[nodiscard]]
    constexpr int countLowerZeroes(T num) {
      int result = binDigits<T>;

      forEachBitLowToHigh(num, [&result](auto b, int bitnum) {
        if(b) {
          result = bitnum;
          return IterationDecision::stop;
        }
        return IterationDecision::keepGoing;
      });

      return result;
    }

    template<typename T>
    [[nodiscard]]
    constexpr int countLowerOnes(T num) {
      int result = binDigits<T>;

      forEachBitLowToHigh(num, [&result](auto b, int bitnum) {
        if(!b) {
          result = bitnum;
          return IterationDecision::stop;
        }
        return IterationDecision::keepGoing;
      });

      return result;
    }

    template<typename T>
    [[nodiscard]]
    constexpr int countHighZeroes(T num) {
      int result = binDigits<T>;

      forEachBitHighToLow(num, [&result](auto b, int bitnum) {
        if(b) {
          result = bitnum;
          return IterationDecision::stop;
        }
        return IterationDecision::keepGoing;
      });

      return result;
    }

    template<typename T>
    [[nodiscard]]
    constexpr int countHighOnes(T num) {
      int result = binDigits<T>;

      forEachBitHighToLow(num, [&result](auto b, int bitnum) {
        if(!b) {
          result = bitnum;
          return IterationDecision::stop;
        }
        return IterationDecision::keepGoing;
      });

      return result;
    }

    template<typename T>
    [[nodiscard]]
    constexpr int populationCount(T num) {
      int sum = 0;
      forEachBitLowToHigh(num, [&sum](auto b, auto bitnum) { sum += b; return IterationDecision::keepGoing; });
      return sum;
    }

    template<typename T>
    [[nodiscard]]
    constexpr int unsetCount(T num) {
      return binDigits<T> - populationCount(num);
    }

    template<auto modulus, typename T>
    [[nodiscard]]
    constexpr auto roundDown(T value) {
      return value - (value % modulus);
    }

    template<auto modulus, typename T>
    [[nodiscard]]
    constexpr auto roundUp(T value) {
      return roundDown<modulus>(value + modulus - 1);
    }

    template<typename Val>
    [[nodiscard]]
    constexpr Val msb(Val value) {
      Val zeroes = countHighZeroes(value);
      if(zeroes == binDigits<Val>)
        return 0;
      return ((Val)1) << zeroes;
    }

    template<typename Val>
    [[nodiscard]]
    constexpr Val lsb(Val value) {
      return value & -value;
    }

    template<typename Val>
    [[nodiscard]]
    constexpr bool isPow2(Val value) {
      return !(value & (value - 1));
    }

    template<typename Val>
    [[nodiscard]]
    constexpr Val pow2Down(Val v) {
      if(v < 1)
        return 1;
      return msb(v);
    }

    template<typename Val>
    [[nodiscard]]
    constexpr Val pow2Up(Val v) {
      if(v < 1)
        return 1;
      /* Shift 1 iff not power of 2 */
      return pow2Down(v) << !isPow2(v);
    }

    template<typename T>
    using Two = std::pair<T, T>;

    template<typename Val, typename Compare>
    [[nodiscard]]
    constexpr Two<Val *> smallerLarger(Val const &lhs, Val const &rhs, Compare &cmp) {
      if(cmp(lhs, rhs))
        return { &lhs, &rhs };
      return { &rhs, &lhs };
    }

    template<typename Func>
    constexpr auto compareValueFunc(Func &&valueFunc) {
      return [f = std::forward<Func>(valueFunc)](auto lhs, auto rhs) {
        return f(lhs) < f(lhs);
      };
    }

    template<typename T, typename Val>
    constexpr auto compareMemberFunc(Val (T::*mfunc)()) {
      return compareValueFunc([mfunc](T &v) {
        return (v.*mfunc)();
      });
    }

    template<typename T, typename Val>
    constexpr auto compareMember(Val T::*memb) {
      return compareValueFunc([memb](T &v) {
        return v.*memb;
      });
    }

    inline void setmem(u8 *data, u8 value, uSz size) {
      while(size--)
        *data++ = value;
    }

    inline void copymem(u8 *dest, u8 const *src, uSz size) {
      while(size--)
      *dest++ = *src++;
    }

    inline bool memeq(u8 const *lhs, u8 const *rhs, uSz size) {
      while(size--) if(*lhs++ != *rhs++)
        return false;
      return true;
    }

    template<typename T>
    [[nodiscard]] constexpr inline T kilo(T val) {
      return T{1024} * val;
    }

    template<typename T>
    [[nodiscard]] constexpr inline T mega(T val) {
      return T{1024} * kilo(val);
    }

    template<typename T>
    [[nodiscard]] constexpr inline T giga(T val) {
      return T{1024} * mega(val);
    }

    template<typename T>
    [[nodiscard]] constexpr inline T tera(T val) {
      return T{1024} * giga(val);
    }

    template<typename T>
    [[nodiscard]] constexpr inline T peta(T val) {
      return T{1024} * tera(val);
    }

    // String literal to constexpr u64
    constexpr u64 genMagic(char const (&dat)[9]) {
      u64 result = 0;
      for(int i = 8; i --> 0;) {
        result <<= 8;
        result  |= (u8)dat[i];
      }
      return result;
    }

    template<typename T>
    struct Range {
      T begin;
      T end;

      constexpr bool overlaps(Range const &other) const {
        return this->contains(other.begin) || this->contains(other.end - T{1}) ||
               other.contains(this->begin) || other.contains(this->end - T{1});
      }

      constexpr bool contains(Range const &other) const {
        return begin <= other.begin && other.end <= end;
      }

      constexpr bool contains(T const &value) const {
        return begin <= value && value < end;
      }

      constexpr bool operator<(Range &other) const {
        return begin < other.begin;
      }

      constexpr auto size() const {
        return end - begin;
      }
    };

    template<typename T>
    T &get(u8 *ptr, u64 offset) {
      return *(T *)(ptr + offset);
    }
  }
}
