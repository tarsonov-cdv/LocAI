# LocAI

<p align="center">
  <b>Private local AI assistant powered by MLX</b><br>
  Run modern language models directly on Apple Silicon devices.
</p>

---

## Overview

LocAI is a native Swift application that allows you to run large language models completely locally on Apple devices.

No cloud APIs.
No external servers.
No data leaving your device.

Models are downloaded and managed directly inside the application, allowing users to keep multiple local models and switch between them whenever needed.

Designed for Apple Silicon devices with a focus on performance, privacy and efficient memory usage.

---

## Features

### 🧠 Local LLM inference

- Fully local AI chat
- MLX acceleration for Apple Silicon
- Streaming token generation
- Native Swift / SwiftUI interface
- Works offline after model download

---

### 🔢 Token counter

- Live estimate of tokens used by the current conversation vs. the loaded model's context window
- Live estimate for the draft you're typing, before you hit send
- Color-coded warning as you approach the context limit
- Backend-agnostic heuristic (~4 characters/token) — no per-keystroke round-trip into the model

---

### 📦 Built-in model manager

LocAI handles model management inside the app:

- Download models directly from the application
- Keep multiple models installed simultaneously
- Switch between downloaded models
- Automatic local model detection
- Delete models with a confirmation prompt (auto-unloads if it's the active model)
- Tap a selected repo/file again to deselect it
- No manual file copying required

Supported formats:

- MLX models
- GGUF models (llama.cpp backend support)

---

### ⚡ Memory optimization

LocAI includes runtime configuration based on available memory:

- Automatic context size adjustment
- GPU memory budgeting
- Cache control
- Memory-aware inference settings

For devices with limited RAM:

- Optimized default configurations
- Reduced KV cache usage
- Smaller context windows

For larger models:

- Optional **forced swap mode**
- Allows running models that exceed normal memory limits by trading performance for compatibility

---

## Supported devices

Designed for Apple Silicon:

- MacBook Air / Pro (M-series)
- iMac Apple Silicon
- Mac mini / Mac Studio
- iPhone and iPad with Apple Silicon

Example:

- MacBook Air M2 8GB
- iPhone 16 Pro Max

---

## Supported models

LocAI works with MLX-compatible models, including:

- Llama 3.2 Instruct
- Qwen Instruct
- Phi models
- Gemma models
- Other MLX community models

Recommended models:

| Model | Size | Usage |
|-|-|-|
| Llama 3.2 3B Instruct 4-bit | ~2GB | Fast general assistant |
| Qwen 2.5 3B Instruct 4-bit | ~2GB | Multilingual assistant |
| Phi-3.5 Mini 4-bit | ~2GB | Lightweight reasoning |
| Qwen 2.5 7B 4-bit | ~4GB+ | Higher quality responses |

---

## Architecture

LocAI is built with:

- Swift
- SwiftUI
- Observation framework
- MLX
- MLXLMCommon
- MLX Swift examples

Architecture:

```
SwiftUI Interface
        |
        |
    AppState
        |
        |
  ChatBackend Protocol
        |
   ----------------
   |              |
 MLX Backend   llama.cpp
   |
 MLX Runtime
   |
 Apple Silicon GPU
```

---

## Privacy

LocAI is designed around local-first AI:

- No API keys required
- No cloud inference
- No telemetry
- No external chat storage
- Your conversations stay on your device

---

## Installation

### Requirements

- macOS / iOS device with Apple Silicon
- Xcode
- Swift toolchain

---

### Build

1. Clone the repository:

```bash
git clone https://github.com/tarsonov-cdv/LocAI.git
cd LocAI
```

2. Open the project:

```bash
open LocAI.xcodeproj
```

3. Build and run using Xcode.

---

## Model setup

Models are downloaded directly inside LocAI.

1. Open the model manager
2. Select a compatible model
3. Download
4. Load the model
5. Start chatting locally

Multiple models can be stored and switched between.

---

## Performance notes

Performance depends on:

- Device RAM
- Model size
- Quantization
- Context length
- Memory configuration

Apple Silicon devices benefit from MLX unified memory architecture, allowing efficient GPU acceleration without dedicated VRAM.

---

## Roadmap

Planned features:

- [ ] Improved generation statistics
- [ ] More llama.cpp backend support
- [ ] Model metadata viewer
- [ ] Conversation export
- [ ] Custom model repositories
- [ ] More languages

---

## License

# PolyForm Noncommercial License 1.0.0

---

## Credits

Built with:

- Apple MLX
- MLX Swift
- Hugging Face model ecosystem
- SwiftUI
