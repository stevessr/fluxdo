cmake_minimum_required(VERSION 3.22.1)
project(pico_xr_qr LANGUAGES CXX)

# The Khronos Android Loader AAR supplies its headers, loader and prefab config.
find_package(OpenXR REQUIRED CONFIG)

add_library(pico_xr_qr SHARED pico_xr_qr.cpp)
target_compile_features(pico_xr_qr PRIVATE cxx_std_17)
target_compile_options(pico_xr_qr PRIVATE -Wall -Wextra -Wno-missing-field-initializers)
target_link_libraries(pico_xr_qr PRIVATE OpenXR::openxr_loader log)
