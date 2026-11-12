# Plugin registration.
#
# Plugin clients (apps that use this plugin) should typically add this file with
# add_subdirectory, which causes it to create a target named
# PACKAGE_NAME_plugin (where PACKAGE_NAME is the first argument of the
# pubspec.yaml file).

# List of absolute paths to all plugin C/C++ files.
list(APPEND PLUGIN_SOURCES
  "${CMAKE_CURRENT_SOURCE_DIR}/clipboard_plugin.cpp"
  "${CMAKE_CURRENT_SOURCE_DIR}/clipboard_plugin.h"
)

# List of absolute paths to all plugin Windows-specific C/C++ files.
list(APPEND PLUGIN_WINDOWS_SOURCES
)

# List of libraries to link against.
list(APPEND PLUGIN_LIBRARIES
  gdiplus
  shlwapi
)

# Create the plugin target
add_library(clipboard_plugin SHARED
  ${PLUGIN_SOURCES}
  ${PLUGIN_WINDOWS_SOURCES}
)

# Apply standard settings
target_compile_features(clipboard_plugin PUBLIC cxx_std_17)
target_compile_options(clipboard_plugin PRIVATE /W4 /WX /wd"4100")
target_compile_options(clipboard_plugin PRIVATE /EHsc)
target_compile_definitions(clipboard_plugin PRIVATE "_HAS_EXCEPTIONS=0")
target_compile_definitions(clipboard_plugin PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
target_compile_definitions(clipboard_plugin PRIVATE "NOMINMAX")

# Link against Flutter plugin wrapper
target_link_libraries(clipboard_plugin PRIVATE flutter_wrapper_plugin)

# Link against required libraries
foreach(lib ${PLUGIN_LIBRARIES})
  target_link_libraries(clipboard_plugin PRIVATE ${lib})
endforeach()

# Set include directories
# The generated code expects <clipboard/clipboard_plugin.h>
# The include path should point to the parent directory so that
# <clipboard/clipboard_plugin.h> resolves correctly
# (CMAKE_CURRENT_SOURCE_DIR is clipboard/windows, parent is clipboard root)
get_filename_component(PLUGIN_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}" DIRECTORY)
get_filename_component(PLUGIN_SYMLINKS_DIR "${PLUGIN_ROOT_DIR}" DIRECTORY)
target_include_directories(clipboard_plugin PUBLIC
  "${PLUGIN_SYMLINKS_DIR}"
  "${CMAKE_CURRENT_SOURCE_DIR}"
)
