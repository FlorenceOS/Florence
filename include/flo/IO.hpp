#pragma once

#include "Ints.hpp"

#include "flo/Util.hpp"
#include "flo/Florence.hpp"
#include "flo/TypeTraits.hpp"
#include "flo/Containers/Array.hpp"

namespace flo {
  enum struct TextColor {
    red,
    cyan,
    yellow,
    white,
    blue,
    green,
  };

  bool colorOverride = false;

  extern void putchar(char c);
  extern void setColor(TextColor col);
  extern void feedLine();

  namespace IO {
    namespace Disk {
      auto constexpr SectorSize = 0x200;
    }
  }

  template<typename Putchar>
  void printString(char const *str, Putchar &&pch) {
    while(*str)
      pch(*str++);
  }

  char const *colorString(TextColor c) {
    switch(c) {
    case TextColor::red:    return "31";
    case TextColor::cyan:   return "36";
    case TextColor::yellow: return "33";
    case TextColor::white:  return "37";
    case TextColor::blue:   return "34";
    case TextColor::green:  return "32";
    default:                return "0";
    }
  }

  void __attribute__((noinline)) printChrArr(char const *arr, uSz size) {
    if(!arr[size - 1])
      --size;

    for(uSz ind = 0; ind < size; ++ ind)
      putchar(arr[ind]);
  }

  void print(char const *str) {
    while(*str)
      putchar(*str++);
  }

  template<bool removeLeadingZeroes = false, bool prefix = false, typename T>
  auto printNum(T num) {
    auto constexpr numChars = flo::Limits<T>::nibbles;

    flo::Array<char, numChars + 1> buf{};
    auto it = buf.rbegin() + 1;
    while(it != buf.rend()) {
      *it++ = "0123456789ABCDEF"[num & T{0xf}];
      num >>= 4;

      if constexpr(removeLeadingZeroes) if(!num)
        break;
    }

    if constexpr(prefix)
      print("0x");
    return print(&*--it);
  }

  template<typename T>
  auto printDec(T num) {
    flo::Array<char, flo::Limits<T>::digits10 + 1> buf{};
    auto it = buf.rbegin();
    do {
      *++it = '0' + (num % 10);
      num /= 10;
    } while(num);

    return print(&*it);
  }

  void __attribute__((noinline)) doColor(TextColor color) {
    if(!exchange(colorOverride, false))
      flo::setColor(color);
  }

  template<typename T>
  struct Printer {
    static __attribute__((noinline)) void print(T const &value) {
      doColor(TextColor::cyan);
      return printNum(value);
    }
  };

  template<>
  struct Printer<char const *> {
    static __attribute__((noinline)) void print(char const *str) {
      doColor(TextColor::white);
      flo::print(str);
    }
  };

  template<typename T>
  struct Printer<Decimal<T>> {
    static __attribute__((noinline)) void print(Decimal<T> const &val) {
      doColor(TextColor::yellow);
      flo::printDec(val.val);
    }
  };

  template<typename T>
  struct Printer<T *> {
    static __attribute__((noinline)) void print(T *val) {
      doColor(TextColor::blue);
      flo::printNum(reinterpret_cast<uptr>(val));
    }
  };

  template<>
  struct Printer<flo::PhysicalAddress> {
    static __attribute__((noinline)) void print(flo::PhysicalAddress addr) {
      doColor(TextColor::green);
      flo::printNum(addr());
    }
  };

  template<>
  struct Printer<flo::VirtualAddress> {
    static __attribute__((noinline)) void print(flo::VirtualAddress addr) {
      doColor(TextColor::yellow);
      flo::printNum(addr());
    }
  };

  template<>
  struct Printer<flo::Spaces> {
    static __attribute__((noinline)) void print(flo::Spaces spaces) {
      doColor(TextColor::white);
      for(int i = 0; i < spaces.numSpaces; ++ i)
        flo::putchar(' ');
    }
  };

  namespace Impl {
    template<typename T>
    void __attribute__((always_inline)) printSingle(T &&val) {
      if constexpr(isSame<decay<T>, TextColor>) {
        setColor(val);
        colorOverride = true;
      }
      else if constexpr(isArrayKnownBounds<removeRef<T>>) {
        if constexpr(isSame<decay<decltype(*val)>, char>) {
          doColor(TextColor::white);
          return flo::printChrArr(val, Util::arrSz(val));
        }
        else
          Printer<decay<T>>::print(val);
      }
      else if constexpr(isIntegral<decay<T>>) {
        doColor(TextColor::cyan);
        printNum(val);
      }
      else
        Printer<decay<T>>::print(val);
    }

    void __attribute__((noinline)) printPrefix(char const *prefix) {
      flo::setColor(TextColor::red);
      flo::print(prefix);
      flo::setColor(TextColor::white);
      flo::print(" ");
    }
  }

  template<bool nopOut>
  constexpr auto makePline(char const *prefix) {
    if constexpr(nopOut)
      return [](auto &&...vs) __attribute__((always_inline)) {};

    else return
      [prefix](auto &&...vs) __attribute__((always_inline)) mutable {
        Impl::printPrefix(prefix);
        (Impl::printSingle(flo::forward<decltype(vs)>(vs)), ...);
        feedLine();
      };
  }
}
