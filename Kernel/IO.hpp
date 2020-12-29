#pragma once

#include "flo/IO.hpp"

namespace Kernel {
  namespace IO {
    using namespace flo::IO;
    using flo::TextColor;

    template<typename T>
    T in(u16 port) {
      T retval;
      asm volatile("in %1, %0":"=a"(retval):"Nd"(port));
      return retval;
    }

    template<typename T, u16 port>
    T in() {
      T retval;
      asm volatile("in %1, %0":"=a"(retval):"Nd"(port));
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

    namespace VGA {
      auto constexpr width = 80;
      auto constexpr height = 25;

      u32 inline currX = 0;
      u32 inline currY = 0;

      u8 inline currentColor = 0x7;

      inline void setColor(TextColor c) {
        switch(c) {
        case TextColor::red:    currentColor = 0x4; break;
        case TextColor::cyan:   currentColor = 0x3; break;
        case TextColor::yellow: currentColor = 0xE; break;
        case TextColor::white:  currentColor = 0x7; break;
        case TextColor::blue:   currentColor = 0x1; break;
        case TextColor::green:  currentColor = 0x2; break;
        default:                currentColor = 0xF; break;
        }
      }

      inline volatile u16 *charaddr(int x, int y) {
        return (volatile u16 *)flo::getPhys<u16>(flo::PhysicalAddress{0xB8000}) + (y * width + x);
      }

      inline void setchar(int x, int y, char c) {
        *charaddr(x, y) = (currentColor << 8) | c;
      }

      inline void setchar(int x, int y, u16 entireChar) {
        *charaddr(x, y) = entireChar;
      }

      inline u16 getchar(int x, int y) {
        return *charaddr(x, y);
      }

      inline void feedLine() {
        currX = 0;
        if(currY == height - 1) {
          // Scroll
          for(int i = 0; i < height - 1; ++ i) for(int x = 0; x < width; ++ x)
              setchar(x, i, getchar(x, i + 1));

          // Clear bottom line
          for(int x = 0; x < width; ++ x)
            setchar(x, height - 1, ' ');
        }
        else
          ++currY;
      }

      inline void putchar(char c) {
        if(currX == width) {
          feedLine();
        }
        setchar(currX++, currY, c);
      }

      inline void clear() {
        for(int x = 0; x < width;  ++ x)
        for(int y = 0; y < height; ++ y)
          setchar(x, y, ' ');
      }
    }

    namespace Debugout {
      inline void write(char c) {
        IO::out<0xE9>(c);
      }

      inline void feedLine() {
        write('\n');
      }

      static inline char const *lastCol = "0";
      inline void setColor(TextColor c) {
        auto str = flo::colorString(c);

        if(str != flo::exchange(lastCol, str)) {
          write('\x1b');
          write('[');
          flo::printString(str, &write);
          write('m');
        }
      }
    }

    namespace Impl {
      template<int port>
      struct Serial {
      private:
        using T = char;
        static constexpr int hwport() {
          if constexpr(port == 1) {
            return 0x3f8;
          }
          else if constexpr(port == 2) {
            return 0x2f8;
          }
          else if constexpr(port == 3) {
            return 0x3e8;
          }
          else if constexpr(port == 4) {
            return 0x2e8;
          }
          else {
            static_assert(port != port, "Invalid port number");
          }
        }
      public:
        static void initialize() {
          IO::out<hwport() + 1>('\x00');
          IO::out<hwport() + 3>('\x80');
          IO::out<hwport() + 0>('\x01');
          IO::out<hwport() + 1>('\x00');
          IO::out<hwport() + 3>('\x03');
          IO::out<hwport() + 2>('\xC7');
        }

        static bool canSend() { return IO::in<T, hwport() + 5>() & 0x20; }
        static void write(char c) {
          if(!c) return;
          while(!canSend()) __asm__("pause");
          IO::out<hwport()>(c);
        }
        static bool hasData() { return IO::in<T, hwport() + 5>() & 0x01; }
        static char read() {
          while(!hasData()) __asm__("pause");
          return IO::in<T, hwport()>();
        }

        static inline char const *lastCol = "0";
        static void setColor(TextColor c) {
          auto str = colorString(c);

          if(flo::exchange(lastCol, str) != str) { // New color
            write('\x1b');
            write('[');
            flo::printString(str, &write);
            write('m');
          }
        }

        static void feedLine() {
          write('\n');
        }
      };
    }

    inline Impl::Serial<1> serial1;
    inline Impl::Serial<2> serial2;
    inline Impl::Serial<3> serial3;
    inline Impl::Serial<4> serial4;
  }
}
