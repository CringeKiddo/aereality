# Repo conventions

Shaderly (AEReality) is a private, offline Flutter + Dart app with a C++ Vulkan FFI core. It is not going public. Target phone: Nuu N20 (8-bit only). CI is GitHub Actions (build-apk.yml).

## Do not delete these files
- lib/export_service.dart
- lib/export_services.dart
- LegacyExportMatrix in lib/constants.dart

Intentionally kept as deprecated fallbacks by the owner.
Zero callers in the live path. Do not delete, rename, or
import them.

## Live export path
export_suite.dart -> export_matrix.dart

## Do not touch
- Anything under assets/shaders/ without reading the
  cross-batch notes in the SUMMARY files.
- UBO size is defined once in vfx_slots.dart as
  Vfx.uboFloats. Never hardcode 6144 or 5376 anywhere else.
  (The C++ side has the same number as `kUboFloats` in vulkan_processor.cpp and the shader has `float reserved[768]`;
  those three must always agree with Vfx.uboFloats. Change all of them together or none.)
- Shader passes are numbered: 1-10 original, 11-12 text
  warp, 13-17 VFX + Sapphire. Do not reuse or renumber.
  (Pass 0 is the primary grade. The next free pass number is 18.)
- Text has its own glow (textGlowDisk). Do not unify with the
  shared glow.

## Batch history
This repo was built in 9 batches. Batch 08 is polish. Batch 09
is Motion S. Do not start Motion S before batch 08 is signed
off.
