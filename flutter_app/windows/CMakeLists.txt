# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(ccloud LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "ccloud")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# === CCloud runner version ===
# One version string shared by the startup log and the build; kept in sync with
# pubspec.yaml instead of a second literal.
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/../pubspec.yaml" CCLOUD_VERSION_LINE
     REGEX "^version:[ ]*[0-9]")
string(REGEX REPLACE "^version:[ ]*" "" CCLOUD_VERSION
       "${CCLOUD_VERSION_LINE}")
string(STRIP "${CCLOUD_VERSION}" CCLOUD_VERSION)
if(CCLOUD_VERSION STREQUAL "")
  set(CCLOUD_VERSION "0.0.0")
endif()
add_compile_definitions("CCLOUD_VERSION=\"${CCLOUD_VERSION}\"")

# === CCloud renderer escape hatch ===
# Release builds keep the Flutter default renderer. A build configured with
# -DCCLOUD_FORCE_SKIA=ON (or a compat.txt next to the exe, handled in the
# runner) disables Impeller. See CCLOUD_HAS_IMPELLER_SWITCH below for why the
# availability of that setter is declared rather than probed.
option(CCLOUD_FORCE_SKIA "Disable Impeller in this build (compatibility build)" OFF)
if(CCLOUD_FORCE_SKIA)
  add_compile_definitions(CCLOUD_DEFAULT_SKIA=1)
elseif(DEFINED ENV{CCLOUD_FORCE_SKIA})
  string(TOUPPER "$ENV{CCLOUD_FORCE_SKIA}" _ccloud_env_force_skia)
  if(_ccloud_env_force_skia MATCHES "^(1|ON|TRUE|YES)$")
    add_compile_definitions(CCLOUD_DEFAULT_SKIA=1)
  endif()
  unset(_ccloud_env_force_skia)
endif()

# === Does this Flutter SDK expose the Impeller switch? ===
# The runner calls flutter::DartProject::set_impeller_switch(), which the
# client-wrapper header of the pinned SDK declares (3.47.8:
# shell/platform/windows/client_wrapper/include/flutter/dart_project.h,
# enum ImpellerSwitch + the setter and getter).
#
# A check_cxx_source_compiles probe against that header is NOT possible at
# configure time, and CI proved it: the tool unpacks the wrapper headers into
# windows/flutter/ephemeral/cpp_client_wrapper only from the flutter_assemble
# build step (build_system/targets/windows.dart copies
# Artifact.windowsCppClientWrapper into the ephemeral dir), while
# build_windows.dart runs _runCmakeGeneration() BEFORE _runBuild(). On a clean
# runner the include directory does not exist yet, so the probe compiled
# nothing, returned an empty cache value and wrote a 0-byte marker (CI run
# 45045859767) - which silently disabled the escape hatch in every package.
#
# So the requirement is stated here instead of guessed: the compat escape hatch
# needs the SDK this repo pins. If the pinned Flutter is ever lowered below the
# version that ships the setter, the compile fails with a plain
# "no member named 'set_impeller_switch'" error in runner/main.cpp, which is
# loud and points straight at this comment - unlike a probe that can only ever
# answer "unsupported".
add_compile_definitions(CCLOUD_HAS_IMPELLER_SWITCH=1)

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")


# package:jni arrives transitively (it is a dependency of the Android
# implementations of shared_preferences/path_provider) and registers itself as a
# Windows FFI plugin. CCloud never uses JNI on Windows, and jni 1.1.0's Windows
# CMakeLists.txt has a broken `set_target_properties(${TARGET_NAME} ...)` call
# that only runs when a JDK is detected. Keep FindJNI disabled so the unused
# helper library is skipped entirely.
set(CMAKE_DISABLE_FIND_PACKAGE_JNI ON)

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
