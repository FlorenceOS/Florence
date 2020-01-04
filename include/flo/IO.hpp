#include "Ints.hpp"

namespace flo {
  namespace IO {
    template<typename T>
    T in(u16 port) {
      T retval;
      asm volatile("in %1, %0":"=a"(retval):"Nd"(port));
      return retval;
    }

    template<typename T, u16 port>
    T in() {
      T retval;
      asm volatile("in %1, %0" : "=a"(retval):"Nd"(port));
      return retval;
    }

    inline auto inb = [](auto port) { return in<u8> (port); };
    inline auto inw = [](auto port) { return in<u16>(port); };
    inline auto inl = [](auto port) { return in<u32>(port); };

    template<typename T>
    void out(u16 port, T value) {
      asm volatile("out %0, %1"::"a"(value),"Nd"(port));
    }

    template<u16 port, typename T>
    void out(T value) {
      asm volatile("out %0, %1"::"a"(value),"Nd"(port));
    }

    inline auto outb = [](auto port, auto value) { out<u8> (port, value); };
    inline auto outw = [](auto port, auto value) { out<u16>(port, value); };
    inline auto outl = [](auto port, auto value) { out<u32>(port, value); };

    inline void waitIO() {
      out<0x80>(0);
    }

    auto inline constexpr vgaWidth = 80;
    auto inline constexpr vgaHeight = 25;

    
  }
}
