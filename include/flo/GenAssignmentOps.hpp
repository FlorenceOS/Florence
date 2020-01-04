#pragma once

namespace flo {
  template<typename Base, typename ValueType>
  struct GenAssignmentOps {
    // Naive impelemtation of assignment operations
    Base &operator<<=(ValueType const &other) { return b() = Base{b()() << other}; }
    Base &operator>>=(ValueType const &other) { return b() = Base{b()() >> other}; }

    Base &operator|= (Base const &other) { return b() = Base{b()() & other()}; }
    Base &operator&= (Base const &other) { return b() = Base{b()() & other()}; }

    Base &operator+= (Base const &other) { return b() = Base{b()() + other()}; }
    Base &operator-= (Base const &other) { return b() = Base{b()() - other()}; }

    Base &operator%= (Base const &other) { return b() = Base{b()() % other()}; }
    Base &operator/= (Base const &other) { return b() = Base{b()() / other()}; }
  private:
    auto &b() { return *static_cast<Base *>(this); }
  };
}
