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
  }
}
