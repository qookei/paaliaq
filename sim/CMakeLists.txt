cmake_minimum_required(VERSION 3.15)
project(sim)

find_package(verilator HINTS $ENV{VERILATOR_ROOT} ${VERILATOR_ROOT})
if (NOT verilator_FOUND)
	message(FATAL_ERROR "Verilator was not found. Either install it, or set the VERILATOR_ROOT environment variable")
endif()

#add_compile_options(-fsanitize=address,undefined -Wall -Wextra)
add_compile_options(-Wall -Wextra)
#add_link_options(-fsanitize=address,undefined)

add_executable(sim sim.cpp cpu.cpp)
verilate(sim TRACE SOURCES ../rtl-new/top.v TOP_MODULE top VERILATOR_ARGS -Wno-width -Wno-fatal)
target_compile_features(sim PUBLIC cxx_std_20)
set_target_properties(sim PROPERTIES EXPORT_COMPILE_COMMANDS true)

add_executable(test test.cpp cpu.cpp)
target_compile_features(test PUBLIC cxx_std_20)
target_link_libraries(test simdjson)
set_target_properties(test PROPERTIES EXPORT_COMPILE_COMMANDS true)
