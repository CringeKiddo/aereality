cmake_minimum_required(VERSION 3.10)
project(vulkan_processor)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find Vulkan
find_package(Vulkan REQUIRED)

# OpenCV for DIS Optical Flow Pyramid tracking (QUIET mode so missing SDK doesn't break build)
find_package(OpenCV QUIET)

# Check if OpenCV exists in the build environment
if(OpenCV_FOUND)
    # Both Vulkan and DIS Optical Flow are compiled when OpenCV is present
    add_library(vulkan_processor SHARED
        vulkan_processor.cpp
        optical_flow_engine.cpp
    )
    target_compile_definitions(vulkan_processor PRIVATE HAVE_OPENCV=1)
    target_include_directories(vulkan_processor PRIVATE
        ${Vulkan_INCLUDE_DIRS}
        ${OpenCV_INCLUDE_DIRS}
        ${CMAKE_CURRENT_SOURCE_DIR}
    )
    target_link_libraries(vulkan_processor
        ${Vulkan_LIBRARIES}
        ${OpenCV_LIBS}
        ${CMAKE_DL_LIBS}
        android
        log
        m
    )
else()
    # When OpenCV is not installed on the system (e.g. GitHub Actions container),
    # compile the Vulkan color grading and GPU compute engine cleanly
    add_library(vulkan_processor SHARED
        vulkan_processor.cpp
    )
    target_include_directories(vulkan_processor PRIVATE
        ${Vulkan_INCLUDE_DIRS}
        ${CMAKE_CURRENT_SOURCE_DIR}
    )
    target_link_libraries(vulkan_processor
        ${Vulkan_LIBRARIES}
        ${CMAKE_DL_LIBS}
        android
        log
        m
    )
endif()
