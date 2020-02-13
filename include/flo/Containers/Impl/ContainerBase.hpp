#pragma once

#include "flo/Containers/Iterator.hpp"

namespace flo {
  template<typename Container>
  struct ContainerBase {
    [[nodiscard]] constexpr auto rbegin()       { return makeReverseIterator(cont().end()); }
    [[nodiscard]] constexpr auto rbegin() const { return makeReverseIterator(cont().end()); }

    [[nodiscard]] constexpr auto rend()       { return makeReverseIterator(cont().begin()); }
    [[nodiscard]] constexpr auto rend() const { return makeReverseIterator(cont().begin()); }

    [[nodiscard]] constexpr auto crbegin() const { return makeReverseIterator(cont().cend()); }
    [[nodiscard]] constexpr auto crend()   const { return makeReverseIterator(cont().cbegin()); }

    [[nodiscard]] constexpr auto empty() const { return cont().size() == 0; }
  private:
    Container       &cont()       { return static_cast<Container       &>(*this); }
    Container const &cont() const { return static_cast<Container const &>(*this); }
  };
}
