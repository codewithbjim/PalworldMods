cmake_minimum_required(VERSION 3.24)
project(PerfectPlacementGamepadInput LANGUAGES CXX)

add_library(PerfectPlacementGamepadInput SHARED src/main.cpp)
target_compile_features(PerfectPlacementGamepadInput PRIVATE cxx_std_20)
target_compile_definitions(PerfectPlacementGamepadInput PRIVATE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
    UNICODE
    _UNICODE
)
target_link_libraries(PerfectPlacementGamepadInput PRIVATE xinput)
set_target_properties(PerfectPlacementGamepadInput PROPERTIES
    OUTPUT_NAME main
    MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"
)
