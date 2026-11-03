cmake_minimum_required(VERSION 3.25)
project(raytracer_native_link LANGUAGES CXX)

if(NOT MLX_INSTALL_PREFIX OR NOT RAYTRACER_OBJECT)
  message(FATAL_ERROR "MLX_INSTALL_PREFIX and RAYTRACER_OBJECT are required")
endif()
if(RAYTRACER_CUDA)
  # Initialize CUDA's implicit runtime/link requirements for imported archives.
  enable_language(CUDA)
endif()

# These exports carry the C++ runtime/platform dependencies of the selected
# backend, including BLAS/LAPACK or CUDA/cuDNN where applicable.
find_package(MLX CONFIG REQUIRED
             PATHS "${MLX_INSTALL_PREFIX}/share/cmake/MLX" NO_DEFAULT_PATH)
# Upstream calls its config MLXC but reports MLX_C to CMake's package helper.
set(FPHSA_NAME_MISMATCHED TRUE)
find_package(MLXC CONFIG REQUIRED
             PATHS "${MLX_INSTALL_PREFIX}/share/cmake/MLXC" NO_DEFAULT_PATH)
unset(FPHSA_NAME_MISMATCHED)

add_executable(ray-tracer "${RAYTRACER_OBJECT}")
set_target_properties(ray-tracer PROPERTIES
  LINKER_LANGUAGE CXX
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
target_link_libraries(ray-tracer PRIVATE mlxc)
