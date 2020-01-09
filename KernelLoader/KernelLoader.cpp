#include "flo/Paging.hpp"
#include "flo/CPU.hpp"
#include "flo/IO.hpp"

#include <algorithm>

using Constructor = void(*)();

extern "C" Constructor constructorsStart;
extern "C" Constructor constructorsEnd;

extern "C" void doConstructors() {
  std::for_each(&constructorsStart, &constructorsEnd, [](Constructor c){
    (*c)();
  });
}

namespace flo {
  void putchar(char c) {
    flo::IO::serial1.write(c);
  }

  void feedLine() {
    flo::IO::serial1.write('\n');
  }

  void setColor(flo::IO::Color col) {
    flo::IO::serial1.setColor(col);
  }
}

namespace {
  auto pline = flo::makePline("[FLORKLOAD] ");
}

extern "C" void unmapLowMemory() {

}

extern "C" void consumeHighPhysicalMemory() {
  pline("Running at ", &consumeHighPhysicalMemory, "!");
  flo::CPU::hang();
}
