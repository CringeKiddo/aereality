cmake_minimum_required(VERSION 3.10)
project(vulkan_processor)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find Vulkan (Included directly in Android NDK API 26+)
find_package(Vulkan REQUIRED)

# Optional OpenCV check - QUIET ensures it never fails if OpenCV is not installed on the runner
find_package(OpenCV QUIET)

# Source files list
set(SOURCES
    vulkan_processor.cpp
    optical_flow_engine.cpp
    realesrgan_ncnn.cpp
)

# Create the shared library
add_library(vulkan_processor SHARED
    ${SOURCES}
)

# Conditional OpenCV definitions
if(OpenCV_FOUND)
    message(STATUS "OpenCV found: ${OpenCV_VERSION}")
    target_compile_definitions(vulkan_processor PRIVATE HAVE_OPENCV=1)
    target_include_directories(vulkan_processor PRIVATE ${OpenCV_INCLUDE_DIRS})
    target_link_libraries(vulkan_processor ${OpenCV_LIBS})
else()
    message(STATUS "OpenCV not found in environment - compiling with native Vulkan pipeline")
endif()

# Core Android & Vulkan link libraries
target_link_libraries(vulkan_processor
    ${Vulkan_LIBRARIES}
    ${CMAKE_DL_LIBS}
    android
    log   # Required for __android_log_print
)

# Include directories
target_include_directories(vulkan_processor PRIVATE
    ${Vulkan_INCLUDE_DIRS}
    ${CMAKE_CURRENT_SOURCE_DIR}
)
