#pragma once

#include "Ints.hpp"
#include "flo/Containers/Array.hpp"

namespace flo {
  // isSame
  template<typename T, typename U> constexpr bool isSame = false;
  template<typename T> constexpr bool isSame<T, T> = true;

  static_assert(isSame<bool, bool> && isSame<int, int>);
  static_assert(!isSame<bool, int>);
  static_assert(!isSame<int &, int>);

  // removeRef
  namespace Impl {
    template<typename T> struct rmref       { using type = T; };
    template<typename T> struct rmref<T &>  { using type = T; };
    template<typename T> struct rmref<T &&> { using type = T; };
  }

  template<typename T> using removeRef = typename Impl::rmref<T>::type;

  static_assert(isSame<removeRef<int &>, int>);
  static_assert(isSame<removeRef<int>, int>);

  // isLValueReference
  template<typename T> constexpr bool isLValueReference = false;
  template<typename T> constexpr bool isLValueReference<T &> = true;

  static_assert(!isLValueReference<int>);
  static_assert(isLValueReference<int &>);
  static_assert(!isLValueReference<int &&>);

  // isArrayUnknownBounds
  template<typename T> constexpr bool isArrayUnknownBounds = false;
  template<typename T> constexpr bool isArrayUnknownBounds<T[]> = true;

  // isArrayKnownBounds
  template<typename T>           constexpr bool isArrayKnownBounds = false;
  template<typename T, uSz size> constexpr bool isArrayKnownBounds<T[size]> = true;

  // isCArray
  template<typename T> constexpr bool isCArray = isArrayUnknownBounds<T> || isArrayKnownBounds<T>;

  // isArray
  template<typename T> constexpr bool isArray = isCArray<T>;
  template<typename T, uSz size> constexpr bool isArray<Array<T, size>> = true;

  static_assert(!isArray<int>);
  static_assert(isArray<int[]>);
  static_assert(isArray<int[3]>);

  // conditional
  namespace Impl {
    template<bool b, typename T, typename U> struct cond { using type = U; };
    template<typename T, typename U> struct cond<true, T, U> { using type = T; };
  }
  template<bool b, typename T, typename U> using conditional = typename Impl::cond<b, T, U>::type;

  static_assert(isSame<bool, conditional<false, int, bool>>);
  static_assert(isSame<int, conditional<true, int, bool>>);

  // removeCV
  namespace Impl {
    template<typename T> struct rmcv                   { using type = T; };
    template<typename T> struct rmcv<T const>          { using type = T; };
    template<typename T> struct rmcv<T volatile>       { using type = T; };
    template<typename T> struct rmcv<T const volatile> { using type = T; };
  }

  template<typename T> using removeCV = typename Impl::rmcv<T>::type;

  static_assert(isSame<removeCV<int const>, int>);
  static_assert(isSame<removeCV<int const volatile>, int>);
  static_assert(isSame<removeCV<int volatile>, int>);
  static_assert(isSame<removeCV<int>, int>);
  static_assert(isSame<removeCV<int const volatile &>, int const volatile &>);

  // isOneOf
  namespace Impl {
    template<typename T, typename ...Options> constexpr bool isOneOf() {
      if constexpr((isSame<T, Options> || ...))
        return true;
      else
        return false;
    }
  }
  template<typename Ty, typename ...Options>
  constexpr bool isOneOf = Impl::isOneOf<Ty, Options...>();

  // isSigned
  namespace Impl {
    template<typename T> constexpr bool isSigned =
      Impl::isOneOf<T,
        signed char,
        signed short,
        signed int,
        signed long,
        signed long long
      >();
  }
  template<typename T> constexpr bool isSigned = Impl::isSigned<removeCV<T>>;  

  static_assert(isSigned<signed char>);
  static_assert(!isSigned<unsigned char>);

  // isUnsigned
  namespace Impl {
    template<typename T> constexpr bool isUnsigned =
      Impl::isOneOf<T,
        unsigned char,
        unsigned short,
        unsigned int,
        unsigned long,
        unsigned long long
      >();
  }
  template<typename T> constexpr bool isUnsigned = Impl::isUnsigned<removeCV<T>>;

  static_assert(!isUnsigned<signed char>);
  static_assert(isUnsigned<unsigned char>);

  // isSignlessIntegral
  namespace Impl {
    template<typename T> constexpr bool isSignlessIntegral =
      Impl::isOneOf<T,
        bool,
        wchar_t, char16_t, char32_t
      >();
  }
  template<typename T> constexpr bool isSignlessIntegral = Impl::isSignlessIntegral<T>;

  // isIntegral
  template<typename T> constexpr bool isIntegral = isSigned<T> || isUnsigned<T> || Impl::isSignlessIntegral<removeCV<T>>;

  static_assert(isIntegral<bool>);
  static_assert(isIntegral<int>);
  static_assert(!isIntegral<float>);

  // isFloatingPoint
  namespace Impl {
    template<typename T> constexpr bool isFloatingPoint = 
      Impl::isOneOf<T,
        float,
        double,
        long double
      >();
  }

  template<typename T> constexpr bool isFloatingPoint = Impl::isFloatingPoint<removeCV<T>>;

  static_assert(!isFloatingPoint<bool>);
  static_assert(!isFloatingPoint<int>);
  static_assert(isFloatingPoint<float>);

  // isScalar
  template<typename T>
  constexpr bool isScalar = isIntegral<T> || isFloatingPoint<T>;

  // removeExtent
  namespace Impl {
    template<typename T>         struct removeExt           { using type = T; };
    template<typename T>         struct removeExt<T[]>      { using type = T; };
    template<typename T, uSz sz> struct removeExt<T[sz]>    { using type = T; };
  }
  template<typename T>
  using removeExtent = typename Impl::removeExt<removeRef<T>>::type;

  static_assert(isSame<removeExtent<int[]>, int>);
  static_assert(isSame<removeExtent<int[3]>, int>);
  static_assert(isSame<removeExtent<int>, int>);

  // removeAllExtents
  namespace Impl {
    template<typename T>         struct removeAllExt        { using type = T; };
    template<typename T>         struct removeAllExt<T[]>   { using type = typename removeAllExt<T>::type; };
    template<typename T, uSz sz> struct removeAllExt<T[sz]> { using type = typename removeAllExt<T>::type; };
  }

  template<typename T>
  using removeAllExtents = typename Impl::removeAllExt<removeRef<T>>::type;

  static_assert(isSame<removeAllExtents<int[3][3]>, int>);
  static_assert(isSame<removeAllExtents<int[2][3]>, int>);
  static_assert(isSame<removeAllExtents<int[3][2]>, int>);
  static_assert(isSame<removeAllExtents<int[2][2]>, int>);
  static_assert(isSame<removeAllExtents<int[3]>, int>);
  static_assert(isSame<removeAllExtents<int[2]>, int>);
  static_assert(isSame<removeAllExtents<int>, int>);

  // isDestructible
  namespace Impl {
    template<typename T>
    constexpr bool isDestructible() {
      if(isSame<T, void> || isArrayUnknownBounds<T>)
        return false;
      if(isScalar<T>)
        return true;
      if constexpr(isCArray<T>)
        return isDestructible<removeAllExtents<T>>();
      return false;
    }
  }
  template<typename T>
  constexpr bool isDestructible = Impl::isDestructible<T>();

  static_assert(isDestructible<int>);

  // decay
  template<typename T>
  using decay = conditional<isCArray<T>, removeExtent<T>*, removeCV<removeRef<T>>>;

  static_assert(isSame<decay<int const>, int>);
  static_assert(isSame<decay<int const volatile>, int>);
  static_assert(isSame<decay<int[3]>, int *>);
  static_assert(isSame<decay<int>, int >);

  // isPointer
  template<typename T> constexpr bool isPointer = false;
  template<typename T> constexpr bool isPointer<T *> = true;

  // isTriviallyDestructible
  template<typename T> constexpr bool isTriviallyDestructible = isDestructible<T> && __has_trivial_destructor(T);

  // enableIf
  namespace Impl {
    template<bool condition, typename T> struct enableIf{};
    template<typename T> struct enableIf<true, T> { using type = T; };
  }

  template<bool condition, typename T = void>
  using enableIf = typename Impl::enableIf<condition, T>::type;

  // isAssignable
  template<typename T, typename Ty>
  constexpr bool isAssignable = __is_assignable(T, Ty); // Intrinsic

  // isMoveAssignable
  template<typename T>
  constexpr bool isMoveAssignable = isAssignable<T &, T &&>;

  // isTriviallyAssignable
  template<typename T, typename Ty>
  constexpr bool isTriviallyAssignable = __is_trivially_assignable(T, Ty); // Intrinsic

  // isTriviallyMoveAssignable
  template<typename T>
  constexpr bool isTriviallyMoveAssignable = isTriviallyAssignable<T, T &&>;

  // isConstructible
  template<typename T, typename ...Args>
  constexpr bool isConstructible = __is_constructible(T, Args...); // Intrinsic

  // isMoveConstructible
  template<typename T>
  constexpr bool isMoveConstructible = isConstructible<T, T &&>;

  // isTriviallyConstructible
  template<typename T, typename ...Args>
  constexpr bool isTriviallyConstructible = __is_trivially_constructible(T, Args...); // Intrinsic

  // isTriviallyMoveConstructible
  template<typename T>
  constexpr bool isTriviallyMoveConstructible = isMoveConstructible<T> && isTriviallyConstructible<T, T&&>;
}
