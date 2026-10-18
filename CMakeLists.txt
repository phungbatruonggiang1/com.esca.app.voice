cmake_minimum_required(VERSION 3.16)
project(esca-voiceapp VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include(GNUInstallDirs)
find_package(PkgConfig REQUIRED)
find_package(Threads REQUIRED)
pkg_check_modules(SDBUSCPP REQUIRED IMPORTED_TARGET sdbus-c++)

find_library(ESCA_UI_LIB NAMES esca-ui REQUIRED)
find_path(ESCA_UI_INCLUDE_DIR esca/ui/window.hpp REQUIRED)

add_executable(esca-voiceapp src/main.cpp)
target_include_directories(esca-voiceapp PRIVATE ${ESCA_UI_INCLUDE_DIR})
target_link_libraries(esca-voiceapp PRIVATE
    ${ESCA_UI_LIB} PkgConfig::SDBUSCPP Threads::Threads)

install(TARGETS esca-voiceapp RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES data/appinfo.json
        DESTINATION ${CMAKE_INSTALL_DATADIR}/esca/applications/vn.sparc.esca.voiceapp)
