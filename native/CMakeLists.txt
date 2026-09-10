cmake_minimum_required(VERSION 3.10)
project(vulkan_processor)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Enable OpenMP for NCNN multithreading
find_package(OpenMP REQUIRED)
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${OpenMP_C_FLAGS}")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${OpenMP_CXX_FLAGS}")

# Find Vulkan (Standard component of Android NDK API 26+)
find_package(Vulkan REQUIRED)

include_directories(${CMAKE_CURRENT_SOURCE_DIR})
include_directories(${Vulkan_INCLUDE_DIRS})

# -----------------------------------------------------------------------------
# Fetch and Link NCNN for Real-ESRGAN Neural AI Upscaling
# -----------------------------------------------------------------------------
set(NCNN_VERSION "20240410")
set(NCNN_URL "https://github.com/Tencent/ncnn/releases/download/${NCNN_VERSION}/ncnn-${NCNN_VERSION}-android-vulkan.zip")
set(NCNN_DIR "${CMAKE_CURRENT_BINARY_DIR}/ncnn_prebuilt")

if(NOT EXISTS "${NCNN_DIR}/include/ncnn/net.h")
    message(STATUS "Downloading NCNN Android Vulkan prebuilts for Real-ESRGAN...")
    file(DOWNLOAD "${NCNN_URL}" "${CMAKE_CURRENT_BINARY_DIR}/ncnn.zip"
         SHOW_PROGRESS
         STATUS NCNN_DOWNLOAD_STATUS)
    list(GET NCNN_DOWNLOAD_STATUS 0 NCNN_STATUS_CODE)
    if(NCNN_STATUS_CODE EQUAL 0)
        execute_process(
            COMMAND ${CMAKE_COMMAND} -E tar -xf "${CMAKE_CURRENT_BINARY_DIR}/ncnn.zip"
            WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
        )
        file(RENAME "${CMAKE_CURRENT_BINARY_DIR}/ncnn-${NCNN_VERSION}-android-vulkan/${ANDROID_ABI}" "${NCNN_DIR}")
    endif()
endif()

if(EXISTS "${NCNN_DIR}/include/ncnn/net.h")
    include_directories("${NCNN_DIR}/include/ncnn")
    link_directories("${NCNN_DIR}/lib")
    set(HAVE_NCNN TRUE)
    add_definitions(-DHAVE_NCNN=1)
else()
    set(HAVE_NCNN FALSE)
endif()

find_package(OpenCV QUIET)

set(SOURCES
    vulkan_processor.cpp
)

if(HAVE_NCNN AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/realesrgan_ncnn.cpp")
    list(APPEND SOURCES realesrgan_ncnn.cpp)
endif()

if(OpenCV_FOUND AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/optical_flow_engine.cpp")
    list(APPEND SOURCES optical_flow_engine.cpp)
    include_directories(${OpenCV_INCLUDE_DIRS})
    add_definitions(-DHAVE_OPENCV=1)
endif()

add_library(vulkan_processor SHARED
    ${SOURCES}
)

target_link_libraries(vulkan_processor
    ${Vulkan_LIBRARIES}
    ${CMAKE_DL_LIBS}
    android
    log
    m
)

if(HAVE_NCNN)
    # Collect every single static library shipped inside NCNN (glslang, MachineIndependent, GenericCodeGen, SPIRV, etc.)
    file(GLOB ALL_NCNN_STATIC_LIBS "${NCNN_DIR}/lib/*.a")

    target_link_libraries(vulkan_processor
        -Wl,--whole-archive
        ${ALL_NCNN_STATIC_LIBS}
        -Wl,--no-whole-archive
        OpenMP::OpenMP_CXX
    )
endif()

if(OpenCV_FOUND)
    target_link_libraries(vulkan_processor
        ${OpenCV_LIBS}
    )
endif()
