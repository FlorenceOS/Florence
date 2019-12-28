#pragma once

#include <cstring>
#include <algorithm>

#include "flo/Containers/Impl/ContainerBase.hpp"

namespace flo {
  template<typename Vector, typename T, typename iterator, typename size_type>
  struct VectorBase: ContainerBase<Vector> {
    [[nodiscard]] constexpr auto       &operator[](size_type ind)       { return begin()[ind]; }
    [[nodiscard]] constexpr auto const &operator[](size_type ind) const { return begin()[ind]; }

    [[nodiscard]] constexpr auto       &front()       { return begin()[0]; }
    [[nodiscard]] constexpr auto const &front() const { return begin()[0]; }

    [[nodiscard]] constexpr auto       &back()       { return begin()[v().size() - 1]; }
    [[nodiscard]] constexpr auto const &back() const { return begin()[v().size() - 1]; }

    [[nodiscard]] constexpr T       *data()       { return v().data_(); }
    [[nodiscard]] constexpr T const *data() const { return v().data_(); }

    [[nodiscard]] constexpr T       *begin()       { return data(); }
    [[nodiscard]] constexpr T const *begin() const { return data(); }

    [[nodiscard]] constexpr T       *end()       { return begin() + v().size(); }
    [[nodiscard]] constexpr T const *end() const { return begin() + v().size(); }

    [[nodiscard]] constexpr T const *cbegin() const { return data(); }
    [[nodiscard]] constexpr T const *cend()   const { return cbegin() + v().size(); }

    constexpr void clear() { while(!this->empty()) pop_back(); }

    constexpr void reserve(size_type new_capacity) {
      if(new_capacity > v().capacity())
        v().grow(new_capacity,
          []() { /* no realloc, noop */ },
          [this](auto newStorageIt, auto newCapacity) { // Realloc, relocate elements
            itMoveConstuctDestroy(newStorageIt, begin(), v().end());
          }
        );
    }

    constexpr void resize(size_type newSize) {
      reserve(newSize);
      
      while(newSize < v().size())
        pop_back();

      while(v().size() < newSize)
        emplace_back();
    }

    // @TODO: at()

    constexpr auto &push_back(T const &value) { return emplace_back(value); }

    constexpr auto insert(iterator pos, T const &value) {
      return &emplace(pos, value);
    }

    template<typename InputBeg, typename InputEnd>
    constexpr auto insert(iterator pos, InputBeg ib, InputEnd ie) {
      auto at = makeElementSpace(pos, std::distance(ib, ie));
      while(ib != ie)
        new (&*at++) T(*ib++);
    }

    template<typename ...Ty>
    constexpr auto emplace(iterator pos, Ty &&...vs) {
      return new (&*makeElementSpace(pos)) T(std::forward<Ty>(vs)...);
    }

    template<typename ...Ty>
    constexpr T &emplace_back(Ty &&...vs) {
      return *new (&*makeElementSpace()) T(std::forward<Ty>(vs)...);
    }

    constexpr void pop_back() {
      destroyRange(v().end() - 1, v().end());
      v().adoptNewSize(v().size() - 1);
    }

    // Invalid for non-movable types
    template<typename Ty = void>
    constexpr auto erase(iterator begin, iterator end) -> std::enable_if_t<std::is_move_assignable_v<T>, Ty>{
      auto const elementsDestroyed = std::distance(begin, end);
      itMove<Forwards>(begin, end, v().end());
      destroyRange(v().end() - elementsDestroyed, v().end());
      v().adoptNewSize(v().size() - elementsDestroyed);
    }

  private:
    [[nodiscard]] constexpr Vector       &v()       { return static_cast<Vector       &>(*this); }
    [[nodiscard]] constexpr Vector const &v() const { return static_cast<Vector const &>(*this); }

    // Makes space for num elements at at
    // Please note that this function invalidates iterators if we grow
    [[nodiscard]]
    constexpr iterator makeElementSpace(iterator at, size_type num = 1) {
      auto const atInd = at - v().begin();
      v().grow(v().size() + num,
        [&v = v(), num, at]() {
          // No realloc

          // Split into two ranges:
          // Elements after at, moves into non-constructed
          itMoveConstuct(v.end(), v.end() - num, v.end());
          // Elements after at, moves into constructed
          itMove<Backwards>(at + num, at, v.end() - num);
        },
        [&v = v(), num, at, atInd](auto newStorageIt, auto newCapacity) {
          // Realloc

          // Move over all elements before at
          itMoveConstuctDestroy(newStorageIt, v.begin(), at);
          // Move over the elements after at
          itMoveConstuctDestroy(newStorageIt + atInd + num, at, v.end());
        }
      );

      v().adoptNewSize(v().size() + num);

      return begin() + atInd;
    }

    // Makes element space at the end
    // Also invalidates iterators if we grow
    [[nodiscard]]
    constexpr iterator makeElementSpace(size_type num = 1) {
      v().grow(v().size() + num, []() { /* No realloc: no-op */ },
        [&v = v()](auto newStorageIt, auto newCapacity) {
          // Realloc

          // Move over all elements
          itMoveConstuctDestroy(newStorageIt, v.begin(), v.end());
        }
      );

      v().adoptNewSize(v().size() + num);

      return v().end() - num;
    }

    constexpr static void itMoveBytes(iterator dest, iterator begin, iterator end) {
      if(begin == end) return;
      std::memmove((u8 *)&*dest, (u8 const *)&*begin, (u8 const *)&*end - (u8 const *)&*begin);
    }

  protected:
    constexpr static void itMoveConstuct(iterator dest, iterator begin, iterator end) {
      if constexpr(std::is_trivially_move_assignable_v<T>)
        itMoveBytes(dest, begin, end);

      // We can do this move in any direction, since we're moving
      // into non-overlapping storage, since it's not constructed
      else while(begin != end)
        new(&*dest++) T(std::move(*begin++));
    }

    constexpr static void destroyRange(iterator begin, iterator end) {
      if constexpr(!std::is_trivially_destructible_v<T>) {
        std::for_each(begin, end, [](T &val) { val.~T(); });
      }
    }

    constexpr static void itMoveConstuctDestroy(iterator dest, iterator begin, iterator end) {
      itMoveConstuct(dest, begin, end);
      if constexpr(!std::is_trivially_move_assignable_v<T>) {
        destroyRange(begin, end);
      }
    }

    struct Forwards{};
    struct Backwards{};

    template<typename direction>
    constexpr static void itMove(iterator dest, iterator begin, iterator end) {
      if(end <= begin)
        return;

      if constexpr(std::is_trivially_move_assignable_v<T>)
        itMoveBytes(dest, begin, end);
      else {
        if constexpr(std::is_same_v<direction, Backwards>) {
          dest += std::distance(begin, end);
          while(begin != end)
            *--dest = std::move(*--end);
        }
        else {
          while(begin != end)
            *dest++ = std::move(*begin++);
        }
      }
    }
  };
}
