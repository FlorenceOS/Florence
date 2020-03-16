#pragma once

#include "flo/TypeTraits.hpp"

#include "flo/Containers/Pointers.hpp"

/*
 * Woop. Type erasure time!
 */

namespace flo {
  template<typename>
  struct Function;

  template<typename RetType, typename ...Args>
  struct Function<RetType(Args...)> {
    using FuncPtr = RetType(*)(Args...);
    Function() {
      funcPtr = nullptr;
      isFuncPtr = true;
    }

    template<typename Functor, typename = flo::enableIf<flo::isConstructible<FuncPtr, Functor>>>
    Function(Functor &&function)
        : funcPtr{flo::forward<Functor>(function)} {
      isFuncPtr = true;
    }

    Function(Function &&other)
        : funcPtr{flo::exchange(other.funcPtr, nullptr)}
      {
      other.isFuncPtr = true;
    }

    // Requires that Allocator::deallocate is a static function
    /*template<typename Functor, template<typename T> typename Allocator>
    Function(Functor &&func, Allocator<CallableImpl<Functor>> alloc = Allocator<CallableImpl<Functor>>{})
        : callable{CustomFreeAlloc{&decltype(alloc)::deallocate}, std::move(func)} {
      isFuncPtr = false;
    }*/

  private:
    template<typename T>
    static constexpr bool isFreer = false;

    template<typename T>
    static constexpr bool isFreer<void(*)(T *)> = true;

    struct Callable {
      virtual ~Callable() { };
      virtual RetType invoke(Args...) = 0;
    };

    using FreeFunc = void (*)(void *);

    struct CustomFreeAlloc {
      template<typename Func>
      CustomFreeAlloc(Func f): func{reinterpret_cast<FreeFunc>(f)} {
        static_assert(isFreer<Func>);
      }

      void deallocate(void *ptr) {
        func(ptr);
      }

    private:
      FreeFunc func;
    };

    template<typename Functor>
    struct CallableImpl final: Callable {
      explicit CallableImpl(Functor &&callable)
        : callable{flo::forward<Functor>(callable)}
        { }
      virtual ~CallableImpl() override final = default;
      virtual RetType invoke(Args... args) override final { return callable(flo::forward<Args>(args)...); }
    private:
      Functor callable;
    };
  public:

    template<template<typename T> typename Allocator, typename Functor>
    static Function make(Functor &&func) {
      using alloc = Allocator<CallableImpl<Functor>>;
      Function f;
      f.callable.alloc() = CustomFreeAlloc{&alloc::deallocate};
      f.isFuncPtr = false;
      return flo::move(f);
    }

    ~Function() {
      // Do some cleanup
      if(!isFuncPtr) {
        auto ptr = decltype(callable)::adopt(flo::Paging::makeCanonical(callable.release()), callable.alloc());
        ptr.reset();
      }
    }

    Function &assign(Function &&other) {
      funcPtr = flo::exchange(other.funcPtr, nullptr);
      other.isFuncPtr = true;
      return *this;
    }

    Function &operator=(Function &&other) {
      return assign(flo::move(other));
    }

    RetType operator()(Args ...args) const {
      if(isFuncPtr)
        return flo::Paging::makeCanonical(funcPtr)(flo::forward<Args>(args)...);
      else
        return flo::Paging::makeCanonical(callable.get())->invoke(flo::forward<Args>(args)...);
    }

    operator bool() const {
      if(isFuncPtr)
        return flo::Paging::makeCanonical(funcPtr);
      else
        return callable;
    }

  private:
    union {
      // Store if this is a function pointer in the top bit
      flo::Bitfield<sizeof(uptr) * 8 - 1, 1> isFuncPtr;
      RetType(*funcPtr)(Args...);
      OwnPtr<Callable, CustomFreeAlloc> callable;
    };
  };
}
