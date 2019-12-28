#pragma once

template<typename Storage, typename Compare = std::less>
struct Heap: Storage, Compare {
  Heap(Compare &comp = {}): Compare{comp} { }

  auto pop() {
    std::pop_heap(begin(), end(), static_cast<Compare &>(*this));
    auto retval = std::move(back());
    pop_back();
    return retval;
  }

  template<typename ...Ty>
  void push(Ty... vs) {
    emplace_back(std::forward<Ty>(vs)...);
    std::push_heap(begin(), end(), static_cast<Compare &>(*this));
  }
}
