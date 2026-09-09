cmake_minimum_required(VERSION 3.10)
project(vulkan_processor)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find Vulkan
find_package(Vulkan REQUIRED)

# OpenCV for DIS Optical Flow Pyramid tracking
find_package(OpenCV REQUIRED)

# Create the shared library containing both the Vulkan pipeline and DIS Optical Flow engine
add_library(vulkan_processor SHARED
    vulkan_processor.cpp
    optical_flow_engine.cpp
)

# Link libraries
target_link_libraries(vulkan_processor
    ${Vulkan_LIBRARIES}
    ${OpenCV_LIBS}
    ${CMAKE_DL_LIBS}
    log   # Required for __android_log_print
)

# Include directories
target_include_directories(vulkan_processor PRIVATE
    ${Vulkan_INCLUDE_DIRS}
    ${OpenCV_INCLUDE_DIRS}
)
