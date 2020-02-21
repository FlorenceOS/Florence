#pragma once

#include "flo/Util.hpp"
#include "flo/Algorithm.hpp"
#include "flo/Containers/Impl/ContainerBase.hpp"

namespace flo {
  template<typename Vector, typename T, typename size_type>
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

    using iterator = T *;
    using const_iterator = T const *;
    using reverse_iterator = ReverseIterator<T *>;
    using const_reverse_iterator = ReverseIterator<T const *>;
    using value_type = T;
    using pointer = T *;
    using const_pointer = T const *;

    constexpr void clear() { while(!this->empty()) pop_back(); }

    constexpr void reserve(size_type new_capacity) {
      if(new_capacity > v().capacity())
        v().template grow<DoNotShrink>(new_capacity,
          []() { /* no realloc, noop */ },
          [beg = begin(), nd = end()](auto newStorageIt, auto newCapacity) { // Realloc, relocate elements
            itMoveConstuctDestroy(newStorageIt, beg, nd);
          }
        );
    }

    constexpr Vector &swap(Vector &other) {
      if(&v() == &other)
        return v();

      if(v().empty() && other.empty())
        return v();

      // Let's make sure that if exactly one is inline, it's v().
      if(!v().isInline() && other.isInline()) {
        other.swap(v());
        return v();
      }

      if(v().isInline()) { // If at least one is inline:
        if(other.isInline()) { // If both are inline, we just have to swap the elements
          auto &[smaller, larger] = Util::smallerLarger(v(), other, Util::compareMemberFunc(&Vector::size));

          itMoveDestruct(smaller->begin() + smaller->size(), larger->data() + smaller->size(), larger->data() + larger->size());

          for(uSz i = 0; i < smaller->size(); ++ i)
            swap(v()[i], other[i]);
        }
        else { // If only v() is inline, we have to move the pointer to v() after moving all the inline elements
          auto outOfLineData = other.data();
          auto outOfLineSize = other.capacity();

          other.makeInline();
          itMoveConstuct(other->begin(), v()->begin(), v()->end());

          v().adoptStorage(outOfLineData, outOfLineSize);

          swapSizes(other);
        }
      }
      else { // None inline, just swap around the data, size and capacity
        auto storageL = v().data(), storageR = other.data();
        auto capacityL = v().capacity(), capacityR = other.capacity();

        v().adoptStorage(storageR, capacityR);
        other.adoptStorage(storageL, capacityL);

        swapSizes(other);
      }
      return v();
    }

    constexpr auto shrink_to_fit() const {
      v().template grow<DoShrinking>(v().size(),
        []() { /* No realloc is a no-op */ },
        [beg = begin(), nd = end()](auto newStorage, auto newCapacity) {
          // Move over elements to new storage
          itMoveConstuctDestroy(newStorage, beg, nd);
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
      auto at = makeElementSpace(pos, distance(ib, ie));
      while(ib != ie)
        new (&*at++) T(*ib++);
    }

    template<typename ...Ty>
    constexpr auto emplace(iterator pos, Ty &&...vs) {
      if(pos == v().end())
        return &emplace_back(forward<Ty>(vs)...);
      return new (&*makeElementSpace(pos)) T(forward<Ty>(vs)...);
    }

    template<typename ...Ty>
    constexpr T &emplace_back(Ty &&...vs) {
      return *new (&*makeElementSpace()) T(forward<Ty>(vs)...);
    }

    constexpr void pop_back() {
      destroyRange(v().end() - 1, v().end());
      v().adoptNewSize(v().size() - 1);
    }

    // Invalid for non-movable types
    template<typename Ty = void>
    constexpr auto erase(iterator begin, iterator end) -> enableIf<isMoveAssignable<T>, Ty> {
      auto const elementsDestroyed = distance(begin, end);
      itMove<Forwards>(begin, end, v().end());
      destroyRange(v().end() - elementsDestroyed, v().end());
      v().adoptNewSize(v().size() - elementsDestroyed);
    }

    template<typename Ty = void>
    constexpr auto erase(iterator element) -> enableIf<isMoveAssignable<T>, Ty> {
      erase(element, element + 1);
    }

  private:
    struct DoShrinking{};
    using DoNotShrink = void;

    [[nodiscard]] constexpr Vector       &v()       { return static_cast<Vector       &>(*this); }
    [[nodiscard]] constexpr Vector const &v() const { return static_cast<Vector const &>(*this); }

    // Makes space for num elements at at
    // Please note that this function invalidates iterators if we grow
    [[nodiscard]]
    constexpr iterator makeElementSpace(iterator at, size_type num = 1) {
      auto const atInd = at - v().begin();
      auto prevSize = v().size();
      v().template grow<DoNotShrink>(v().size() + num,
        [&v = v(), num, at]() {
          // No realloc

          // Split into two ranges:
          // Elements after at, moves into non-constructed
          itMoveConstuct(v.end(), v.end() - num, v.end());
          // Elements after at, moves into constructed
          itMove<Backwards>(at + num, at, v.end() - num);
        },
        [num, at, atInd, beg = begin(), nd = end()](auto newStorageIt, auto newCapacity) {
          // Realloc

          // Move over all elements before at
          itMoveConstuctDestroy(newStorageIt, beg, at);
          // Move over the elements after at
          itMoveConstuctDestroy(newStorageIt + atInd + num, at, nd);
        }
      );

      v().adoptNewSize(prevSize + num);

      return begin() + atInd;
    }

    // Makes element space at the end
    // Also invalidates iterators if we grow
    [[nodiscard]]
    constexpr iterator makeElementSpace(size_type num = 1) {
      v().template grow<DoNotShrink>(v().size() + num, []() { /* No realloc: no-op */ },
        [beg = begin(), nd = end()](auto newStorageIt, auto newCapacity) {
          // Realloc

          // Move over all elements
          itMoveConstuctDestroy(newStorageIt, beg, nd);
        }
      );

      v().adoptNewSize(v().size() + num);

      return v().end() - num;
    }

    constexpr static void itMoveBytes(iterator dest, iterator begin, iterator end) {
      if(begin >= end) return;
      Util::movemem((u8 *)&*dest, (u8 const *)&*begin, (u8 const *)&*end - (u8 const *)&*begin);
    }

    constexpr void swapSizes(Vector &other) {
      auto mySize = v().size();
      v().adoptNewSize(other.size());
      other.adoptNewSize(mySize);
    }

  protected:
    constexpr static void itMoveConstuct(iterator dest, iterator begin, iterator end) {
      if constexpr(isTriviallyMoveConstructible<T>)
        itMoveBytes(dest, begin, end);

      // We can do this move in any direction, since we're moving
      // into non-overlapping storage, since it's not constructed
      else while(begin < end)
        new(&*dest++) T(move(*begin++));
    }

    constexpr static void destroyRange(iterator begin, iterator end) {
      if constexpr(!isTriviallyDestructible<T>) {
        forEach(begin, end, [](T &val) { val.~T(); });
      }
    }

    constexpr static void itMoveConstuctDestroy(iterator dest, iterator begin, iterator end) {
      itMoveConstuct(dest, begin, end);
      if constexpr(!isTriviallyMoveAssignable<T>) {
        destroyRange(begin, end);
      }
    }

    struct Forwards{};
    struct Backwards{};

    template<typename direction>
    constexpr static void itMove(iterator dest, iterator begin, iterator end) {
      if(end <= begin)
        return;

      if constexpr(isTriviallyMoveAssignable<T>)
        itMoveBytes(dest, begin, end);
      else {
        if constexpr(isSame<direction, Backwards>) {
          dest += distance(begin, end);
          while(begin != end)
            *--dest = move(*--end);
        }
        else {
          while(begin != end)
            *dest++ = move(*begin++);
        }
      }
    }
  };
}
