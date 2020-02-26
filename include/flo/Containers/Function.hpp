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
    Function(Functor &&function): funcPtr{flo::forward<Functor>(function)} {
      isFuncPtr = true;
    }

    /* @TODO: make this, allocator, etc
    template<typename Functor>
    Function(Functor &&func) {
      isFuncPtr = false;
    }*/

    ~Function() {
      // Do some cleanup
      if(isFuncPtr) {
        auto ptr = OwnPtr<Callable>::adopt(flo::Paging::makeCanonical(callable.release()));
        ptr.reset();
      }
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

    struct Callable {
      virtual ~Callable() { };
      virtual RetType invoke(Args...) const = 0;
    };

    template<typename Functor>
    struct CallableImpl final: Callable {
      explicit CallableImpl(Functor &&callable)
        : callable{flo::forward<Functor>(callable)}
      { }
      ~CallableImpl() final = default;
      RetType invoke(Args... args) final { return callable(flo::forward<Args>(args)...); }
    private:
      Functor callable;
    };

    union {
      // Store if this is a function pointer in the top bit
      flo::Bitfield<sizeof(uptr) * 8 - 1, 1> isFuncPtr;
      RetType(*funcPtr)(Args...);
      OwnPtr<Callable> callable;
    };
  };

}
