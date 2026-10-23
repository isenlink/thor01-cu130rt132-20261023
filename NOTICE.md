# Notice

- `llama.cpp` source and the production patch are derived from
  `ggml-org/llama.cpp`, MIT License. The upstream license text is in `LICENSE`.
- The binaries in `artifacts/` were built locally from the patched source tree
  identified in `SOURCE.md`. They are provided under the same MIT terms as the
  underlying llama.cpp code, without warranty.
- NVIDIA CUDA runtime, cuBLAS and cuda-compat-orin are proprietary NVIDIA
  software. They are **not** included in this release; obtain them from the
  official sources listed in `RUNTIME.md` and follow NVIDIA's license.
- Model weights and model licenses are **not** included. The paths and hashes in
  `SOURCE.md`/`DEPLOY.md` identify the assets used for validation, not a grant
  to redistribute them.
