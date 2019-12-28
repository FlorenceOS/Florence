cmake_minimum_required(VERSION 3.1)

project(tests)

configure_file(CMakeLists.txt.in googletest-download/CMakeLists.txt)
execute_process(COMMAND ${CMAKE_COMMAND} -G "${CMAKE_GENERATOR}" .
  RESULT_VARIABLE result
  WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/googletest-download )
if(result)
  message(FATAL_ERROR "CMake step for googletest failed: ${result}")
endif()
execute_process(COMMAND ${CMAKE_COMMAND} --build .
  RESULT_VARIABLE result
  WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/googletest-download )
if(result)
  message(FATAL_ERROR "Build step for googletest failed: ${result}")
endif()

set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)

add_subdirectory(${CMAKE_CURRENT_BINARY_DIR}/googletest-src
                 ${CMAKE_CURRENT_BINARY_DIR}/googletest-build
                 EXCLUDE_FROM_ALL)

if (CMAKE_VERSION VERSION_LESS 2.8.11)
  include_directories("${gtest_SOURCE_DIR}/include")
endif()

include_directories("${gmock_SOURCE_DIR}/include")

set(CMAKE_CXX_FLAGS "-Werror -fsanitize=address,undefined -Wall -Wno-sign-compare")

file(GLOB TestSources "*.cpp")
add_executable(tests ${TestSources})
target_include_directories(tests PRIVATE ".")
target_include_directories(tests PRIVATE "../include")
set_property(TARGET tests PROPERTY CXX_STANDARD 17)
set_property(TARGET tests PROPERTY CMAKE_CXX_STANDARD_REQUIRED ON)
target_link_libraries(tests gtest_main)
add_test(NAME example_test COMMAND tests)
