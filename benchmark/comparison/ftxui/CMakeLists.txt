cmake_minimum_required(VERSION 3.24)
project(ftxui_comparison LANGUAGES CXX)
include(FetchContent)
set(FTXUI_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(FTXUI_BUILD_DOCS OFF CACHE BOOL "" FORCE)
set(FTXUI_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(FTXUI_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
FetchContent_Declare(ftxui
  URL https://codeload.github.com/ArthurSonzogni/FTXUI/tar.gz/5cfed50702f52d51c1b189b5f97f8beaf5eaa2a6
  URL_HASH SHA256=7a61f2b5519ce42840da9f035297c5e61e4ed8210b9ed990a0138bf31e48ba59)
FetchContent_Declare(json
  URL https://codeload.github.com/nlohmann/json/tar.gz/refs/tags/v3.12.0
  URL_HASH SHA256=4b92eb0c06d10683f7447ce9406cb97cd4b453be18d7279320f7b2f025c10187)
FetchContent_MakeAvailable(ftxui json)
add_executable(ftxui-comparison main.cpp)
target_compile_features(ftxui-comparison PRIVATE cxx_std_17)
target_link_libraries(ftxui-comparison PRIVATE ftxui::component ftxui::dom ftxui::screen nlohmann_json::nlohmann_json)
