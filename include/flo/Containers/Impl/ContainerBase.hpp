#pragma once

namespace flo {
  template<typename Container>
  struct ContainerBase {
    [[nodiscard]] constexpr auto rbegin()       { return std::make_reverse_iterator(cont().end()); }
    [[nodiscard]] constexpr auto rbegin() const { return std::make_reverse_iterator(cont().end()); }

    [[nodiscard]] constexpr auto rend()       { return std::make_reverse_iterator(cont().begin()); }
    [[nodiscard]] constexpr auto rend() const { return std::make_reverse_iterator(cont().begin()); }

    [[nodiscard]] constexpr auto crbegin() const { return std::make_reverse_iterator(cont().cend()); }
    [[nodiscard]] constexpr auto crend()   const { return std::make_reverse_iterator(cont().cbegin()); }

    [[nodiscard]] constexpr auto empty() const { return cont().size() == 0; }
  private:
    Container       &cont()       { return static_cast<Container       &>(*this); }
    Container const &cont() const { return static_cast<Container const &>(*this); }
  };
}
