#include "Testing.hpp"

#include "flo/Assert.hpp"
#include "flo/IO.hpp"

#include <iostream>

void flo::assertionFailure(char const *file, unsigned long long line, char const *message) {
  std::cerr << "Assertion failure at " << file << ":" << line << ": " << message;
  exit(-1);
}

void flo::feedLine() {
  std::cout << '\n';
}

void flo::putchar(char c) {
  std::cout << c;
}

void flo::setColor(flo::TextColor tc) {

}
