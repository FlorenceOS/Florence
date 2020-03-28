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

      // This will call some void (*)(T *) function as void (*)(void *)
      __attribute__((no_sanitize("function")))
      void deallocate(void *ptr) {
        if(ptr) {
          auto cf = flo::Paging::makeCanonical(func);
          if(cf)
            cf(ptr);
        }
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

    Function(OwnPtr<Callable, CustomFreeAlloc> &&ptr)
        :callable{flo::move(ptr)}
      {
      isFuncPtr = false;
    }
  public:

    template<template<typename T> typename Allocator, typename Functor>
    static Function make(Functor &&func) {
      using ci = CallableImpl<flo::removeRef<Functor>>;
      auto heapFunctor = OwnPtr<ci, Allocator<ci>>::make(flo::move(func));
      auto funcPtr = OwnPtr<Callable, CustomFreeAlloc>{{static_cast<Callable *>(heapFunctor.release()), CustomFreeAlloc{&Allocator<ci>::deallocate}}};
      return {flo::move(funcPtr)};
    }

    ~Function() {
      // Do some cleanup
      if(!isFuncPtr) {
        callable.reset();
      }
    }

    Function &assign(Function &&other) {
      this->~Function();
      callable = flo::move(other.callable);
      other.funcPtr = nullptr;
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
        return callable->invoke(flo::forward<Args>(args)...);
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
