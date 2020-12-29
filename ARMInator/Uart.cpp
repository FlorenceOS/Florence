#include "Ints.hpp"

struct Uart {
  u32 data;
  u32 unk_4[8];
  u32 IBRD;
  u32 unk_28[2];
  u32 CR;
};

auto uart = (Uart volatile *)0x9000000;

void __attribute__((constructor)) init() {
  uart->IBRD = 0x10;
  uart->CR = 0xC301;
}
