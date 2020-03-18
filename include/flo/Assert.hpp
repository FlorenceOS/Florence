#pragma once

#include "Ints.hpp"

#define assert(cond)          do { if(!(cond)) flo::assertionFailure(__FILE__, __LINE__, #cond); } while(0)
#define assert_err(cond, err) do { if(!(cond)) flo::assertionFailure(__FILE__, __LINE__, err); } while(0)
#define assert_not_reached()  do {             flo::assertionFailure(__FILE__, __LINE__, "Should be unreachable!"); } while(0)

#define expect(cond)          do { if(!(cond)) flo::unexpected(__FILE__, __LINE__, #cond); } while(0)
#define expect_err(cond, err) do { if(!(cond)) flo::unexpected(__FILE__, __LINE__, err); } while(0)
#define expect_not_reached()  do {             flo::unexpected(__FILE__, __LINE__, "Should be unreachable!"); } while(0)

namespace flo {
  [[noreturn]]
  void assertionFailure(char const *file, u64 line, char const *error);
  void unexpected(char const *file, u64 line, char const *problem);
}
