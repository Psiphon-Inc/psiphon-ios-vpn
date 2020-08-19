# For more information about using CMake with Android Studio, read the
# documentation: https://d.android.com/studio/projects/add-native-code.html

cmake_minimum_required(VERSION 3.4.1)

set(CMAKE_CXX_STANDARD 14)

add_definitions(-DTESTING)

file (GLOB SOURCES "*.cpp")
list(FILTER SOURCES EXCLUDE REGEX "(.*_test\\.cpp)|(test_.*\\.cpp)$")
file (GLOB TEST_SOURCES "*.cpp")
list(FILTER TEST_SOURCES INCLUDE REGEX "(.*_test\\.cpp)|(test_.*\\.cpp)$")
#message("SOURCES: ${SOURCES}")
#message("TEST_SOURCES: ${TEST_SOURCES}")

if(MSVC)
    # From https://stackoverflow.com/questions/10113017/setting-the-msvc-runtime-in-cmake
    # Default to statically-linked runtime.
    if("${MSVC_RUNTIME}" STREQUAL "")
        set(MSVC_RUNTIME "static")
    endif()

    # Set compiler options.
    set(variables
        CMAKE_C_FLAGS_DEBUG
        CMAKE_C_FLAGS_MINSIZEREL
        CMAKE_C_FLAGS_RELEASE
        CMAKE_C_FLAGS_RELWITHDEBINFO
        CMAKE_CXX_FLAGS_DEBUG
        CMAKE_CXX_FLAGS_MINSIZEREL
        CMAKE_CXX_FLAGS_RELEASE
        CMAKE_CXX_FLAGS_RELWITHDEBINFO
    )
    if(${MSVC_RUNTIME} STREQUAL "static")
        message(STATUS "MSVC -> forcing use of statically-linked runtime.")
        foreach(variable ${variables})
        if(${variable} MATCHES "/MD")
            string(REGEX REPLACE "/MD" "/MT" ${variable} "${${variable}}")
        endif()
        endforeach()
    else()
        message(STATUS "MSVC -> forcing use of dynamically-linked runtime.")
        foreach(variable ${variables})
        if(${variable} MATCHES "/MT")
            string(REGEX REPLACE "/MT" "/MD" ${variable} "${${variable}}")
        endif()
        endforeach()
    endif()
endif()

add_library( # Sets the name of the library.
             psicash

             # Sets the library as a static library.
             STATIC

             # Provides a relative path to your source file(s).
             ${SOURCES} )

# TODO: Coverage stuff should not be done unconditionally
SET(GCC_COVERAGE_COMPILE_FLAGS "-Wall -fprofile-arcs -ftest-coverage -g -O0")
SET(CMAKE_CXX_FLAGS  "${CMAKE_CXX_FLAGS} ${GCC_COVERAGE_COMPILE_FLAGS}")

SET(GCC_COVERAGE_LINK_FLAGS    "-lgcov --coverage")
#SET(GCC_COVERAGE_LINK_FLAGS    "-lclang_rt.profile_osx -L/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/clang/10.0.0/lib/darwin")
#SET(CMAKE_EXE_LINKER_FLAGS  "${CMAKE_EXE_LINKER_FLAGS} ${GCC_COVERAGE_LINK_FLAGS}")


# TODO: Test building should not be done unconditionally
###################################
### GTEST
# https://github.com/google/googletest/tree/master/googletest

# Download and unpack googletest at configure time
configure_file(CMakeLists.txt.in googletest-download/CMakeLists.txt)
execute_process(COMMAND ${CMAKE_COMMAND} -G "${CMAKE_GENERATOR}" .
        RESULT_VARIABLE result
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/googletest-download )
if(result)
    message(FATAL_ERROR "CMake step for googletest failed: ${result}")
endif()
execute_process(COMMAND ${CMAKE_COMMAND} --build .
        RESULT_VARIABLE result
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}/googletest-download )
if(result)
    message(FATAL_ERROR "Build step for googletest failed: ${result}")
endif()


# Prevent overriding the parent project's compiler/linker
# settings on Windows
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)

# Prevent Gtest from using pthreads (multithreaded execution)
set(gtest_disable_pthreads ON CACHE BOOL "" FORCE)


# Add googletest directly to our build. This defines
# the gtest and gtest_main targets.
add_subdirectory(${CMAKE_BINARY_DIR}/googletest-src
        ${CMAKE_BINARY_DIR}/googletest-build
        EXCLUDE_FROM_ALL)

# Now simply link against gtest or gtest_main or gmock_main as needed.
add_executable(runUnitTests ${TEST_SOURCES})
target_link_libraries(runUnitTests gmock_main)
target_link_libraries(runUnitTests psicash)
#add_test(NAME example_test COMMAND runUnitTests)
