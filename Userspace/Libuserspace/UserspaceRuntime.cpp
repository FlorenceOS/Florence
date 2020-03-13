#include "Runtime.hpp"

#include "flo/Assert.hpp"
#include "flo/Util.hpp"

extern int main();

extern "C" void runMain() {
  auto rc = main();
  assert_err(rc, "Main exited with nonzero!");
}

void flo::exit() {
  asm("syscall"::"rax"(0));
  assert_not_reached();
}

void flo::ping() {
  asm("syscall"::"rax"(1));
}

void flo::crash(char const *filename, u64 line, char const *errorMessage) {
  asm("syscall"::
    "rax"(3),
    "rbx"(filename),
    "rcx"(Util::strlen(filename)),
    "rdx"(line),
    "rdi"(errorMessage),
    "rsi"(Util::strlen(errorMessage))
  );
  assert_not_reached();
}

void flo::warn(char const *filename, u64 line, char const *errorMessage) {
  asm("syscall"::
    "rax"(4),
    "rbx"(filename),
    "rcx"(Util::strlen(filename)),
    "rdx"(line),
    "rdi"(errorMessage),
    "rsi"(Util::strlen(errorMessage))
  );
}
