#include "Ints.hpp"

#include "flo/Florence.hpp"

#include <limits>
#include <array>

namespace flo {
  template<typename T>
  struct IsDecimal { static constexpr bool value = false; };
  template<typename T>
  struct IsDecimal<Decimal<T>> { static constexpr bool value = true; };

  namespace IO {
    enum struct Color {
      red,
      cyan,
      yellow,
      white,
      blue,
    };
  }

  extern void putchar(char c);
  extern void setColor(IO::Color col);
  extern void feedLine();

  namespace IO {
    template<typename T>
    T in(u16 port) {
      T retval;
      asm volatile("in %0, %1":"=a"(retval):"Nd"(port));
      return retval;
    }

    template<typename T, u16 port>
    T in() {
      T retval;
      asm volatile("in %0, %1":"=a"(retval):"Nd"(port));
      return retval;
    }

    inline auto inb = [](auto port) { return in<u8> (port); };
    inline auto inw = [](auto port) { return in<u16>(port); };
    inline auto inl = [](auto port) { return in<u32>(port); };

    template<typename T>
    void out(u16 port, T value) {
      asm volatile("out %1, %0"::"a"(value),"Nd"(port));
    }

    template<u16 port, typename T>
    void out(T value) {
      asm volatile("out %1, %0"::"a"(value),"Nd"(port));
    }

    inline auto outb = [](auto port, auto value) { out<u8> (port, value); };
    inline auto outw = [](auto port, auto value) { out<u16>(port, value); };
    inline auto outl = [](auto port, auto value) { out<u32>(port, value); };

    inline void waitIO() {
      out<0x80>(0);
    }

    namespace Disk {
      auto constexpr SectorSize = 0x200;
    }

    namespace VGA {
      auto constexpr width = 80;
      auto constexpr height = 25;

      auto inline currX = 0;
      auto inline currY = 0;

      u8 inline currentColor = 0x7;

      void setColor(Color c) {
        switch(c) {
          break; case Color::red:    currentColor = 0x4;
          break; case Color::cyan:   currentColor = 0x3;
          break; case Color::yellow: currentColor = 0xE;
          break; case Color::white:  currentColor = 0x7;
          break; case Color::blue:   currentColor = 0x1;
          break; default:            currentColor = 0xF;
        }
      }

      volatile u16 *charaddr(int x, int y) {
        return (volatile u16 *)flo::getPhys<u16>(flo::PhysicalAddress{0xB8000}) + (y * width + x);
      }

      void setchar(int x, int y, char c) {
        *charaddr(x, y) = (currentColor << 8) | c;
      }

      void setchar(int x, int y, u16 entireChar) {
        *charaddr(x, y) = entireChar;
      }

      u16 getchar(int x, int y) {
        return *charaddr(x, y);
      }

      void feedLine() {
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

      void putchar(char c) {
        if(currX == width) {
          feedLine();
        }
        setchar(currX++, currY, c);
      }

      void clear() {
        for(int x = 0; x < width;  ++ x)
        for(int y = 0; y < height; ++ y)
          setchar(x, y, ' ');
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
        void initialize() {
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

        char const *lastCol = "0";
        void setColor(Color c) {
          auto col = [this](char const *colorString) {
            if(colorString == std::exchange(lastCol, colorString))
              return;

            write('\x1b');
            write('[');
            while(*colorString)
              write(*colorString++);
            write('m');
          };

          switch(c) {
            break; case Color::red:    col("31");
            break; case Color::cyan:   col("36");
            break; case Color::yellow: col("33");
            break; case Color::white:  col("37");
            break; case Color::blue:   col("34");
            break; default:            col("0");
          }
        }

        void feedLine() {
          write('\n');
        }
      };
    }

    inline Impl::Serial<1> serial1;
    inline Impl::Serial<2> serial2;
    inline Impl::Serial<3> serial3;
    inline Impl::Serial<4> serial4;
  }

  template<typename T>
  struct IsSpaces { static constexpr bool value = false; };
  template<>
  struct IsSpaces<Spaces> { static constexpr bool value = true; };

  void print(char const *str) {
    while(*str)
      putchar(*str++);
  }

  template<bool removeLeadingZeroes = false, bool prefix = false, typename T>
  auto printNum(T num) {
    auto constexpr numChars = std::numeric_limits<T>::digits/4;

    std::array<char, numChars + 1> buf{};
    auto it = buf.rbegin() + 1;
    while(it != buf.rend()) {
      *it++ = "0123456789ABCDEF"[num & T{0xf}];
      num >>= 4;

      if constexpr(removeLeadingZeroes) if(!num)
        break;
    }

    if constexpr(prefix)
      print("0x");
    return print(&*--it);
  }

  template<typename T>
  auto printDec(T num) {
    std::array<char, std::numeric_limits<T>::digits10 + 1> buf{};
    auto it = buf.rbegin();
    do {
      *++it = '0' + (num % 10);
      num /= 10;
    } while(num);

    return print(&*it);
  }

  template <bool nopOut>
  constexpr auto makePline(char const *prefix) {
    if constexpr(nopOut)
      return [](auto &&...vs) {};

    else return
      [prefix](auto &&...vs) {
        auto p = [](auto &&val) {
          if constexpr(IsDecimal<std::decay_t<decltype(val)>>::value) {
            setColor(IO::Color::yellow);
            return printDec(val.val);
          }
          else if constexpr(std::is_convertible_v<decltype(val), char const *>) {
            setColor(IO::Color::white);
            return print(val);
          }
          else if constexpr(IsSpaces<std::decay_t<decltype(val)>>::value) {
            setColor(IO::Color::white);
            for(int i = 0; i < val.numSpaces; ++ i)
              putchar(' ');
          }
          else if constexpr(std::is_pointer_v<std::decay_t<decltype(val)>>) {
            setColor(IO::Color::blue);
            return printNum(reinterpret_cast<uptr>(val));
          }
          else {
            setColor(IO::Color::cyan);
            return printNum(val);
          }
        };

        setColor(IO::Color::red);
        print(prefix);
        (p(std::forward<decltype(vs)>(vs)), ...);
        feedLine();
      };
  }
}
