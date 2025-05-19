#!/bin/zsh

if [[ ! -f shaders/shader.glsl ]]; then
  echo "Error: shader.glsl not found in the current directory"
  exit 1
fi

./sokol/fips-deploy/sokol-tools/osx-xcode-release/sokol-shdc -i shaders/shader.glsl -o src/shader.glsl.zig -l metal_macos -f sokol_zig
