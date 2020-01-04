#include "flo/IO.hpp"

namespace flo {
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
  };

  inline Serial<1> serial1;
  inline Serial<2> serial2;
  inline Serial<3> serial3;
  inline Serial<4> serial4;
}
