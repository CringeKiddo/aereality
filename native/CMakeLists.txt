cmake_minimum_required(VERSION 3.10)
project(vulkan_processor)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Optimization flags for high-throughput 60 FPS mobile grading
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3 -ffast-math -flto")

# Enable OpenMP for parallel CPU fallback grading
find_package(OpenMP REQUIRED)
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${OpenMP_C_FLAGS}")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${OpenMP_CXX_FLAGS}")

# Find Android Vulkan Native Library
find_package(Vulkan REQUIRED)

include_directories(${CMAKE_CURRENT_SOURCE_DIR})
include_directories(${Vulkan_INCLUDE_DIRS})

set(SOURCES
    vulkan_processor.cpp
)

add_library(vulkan_processor SHARED
    ${SOURCES}
)

target_link_libraries(vulkan_processor
    ${Vulkan_LIBRARIES}
    ${CMAKE_DL_LIBS}
    OpenMP::OpenMP_CXX
    android
    log
    m
)
