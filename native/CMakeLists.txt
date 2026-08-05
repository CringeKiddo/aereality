cmake_minimum_required(VERSION 3.10)
project(vulkan_processor)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find Vulkan
find_package(Vulkan REQUIRED)

# The main source file
add_library(vulkan_processor SHARED vulkan_processor.cpp)

target_link_libraries(vulkan_processor
    ${Vulkan_LIBRARIES}
    ${CMAKE_DL_LIBS}
)

target_include_directories(vulkan_processor PRIVATE ${Vulkan_INCLUDE_DIRS})
