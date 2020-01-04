#include <array>
#include <cstdint>
#include <bitset>

#include "Ints.hpp"

namespace Flo {
  namespace Impl {
    struct FreeList {
      struct Iterator {
        FreeList const *it;
        constexpr Iterator &operator++();
        constexpr FreeList const *operator*() const { return it; }
        constexpr bool operator==(Iterator const &other) const { return it == other.it; }
        constexpr bool operator!=(Iterator const &other) const { return it != other.it; }
      };

      FreeList *next;

      void emplace(void *v) {
        auto newHead = reinterpret_cast<FreeList *>(v);
        newHead->next = next;
        next = newHead;
      }

      auto begin() const { Iterator{next}; }
      auto end()   const { Iterator{nullptr}; }
      auto empty() const { return next == nullptr; }

      void *extract() { return std::exchange(next, next->next); }
    };
  }

  template<uSz maxAllocSz, uSz minAllocSz>
  struct Balloc {
    
  };
}

