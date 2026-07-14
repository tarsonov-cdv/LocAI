# LocAI

<p align="center">
  <b>Private local AI assistant powered by MLX</b><br>
  Run large language models directly on Apple devices without cloud APIs.
</p>

---

## Overview

LocAI is a native SwiftUI application for running large language models locally on Apple Silicon devices.

The goal of the project is to provide a simple, privacy-focused AI assistant that works completely offline. Models run directly on the device using Apple's MLX framework.

No API keys.  
No cloud processing.  
No external servers.

Your conversations stay on your device.

---

## Features

### Current

- ✅ Native SwiftUI interface
- ✅ macOS support
- ✅ iOS support
- ✅ Local model loading
- ✅ MLX inference backend
- ✅ Streaming responses
- ✅ Configurable memory limits
- ✅ Custom system prompts
- ✅ Optional text filtering
- ✅ Multi-language support
- ✅ Offline operation

### Planned

- [ ] Token counter
- [ ] Tokens per second display
- [ ] Model download manager improvements
- [ ] llama.cpp GGUF backend
- [ ] Chat history persistence
- [ ] Model performance statistics
- [ ] More MLX model formats
- [ ] iPad optimization

---

## Supported Platforms

| Platform | Status |
|---|---|
| macOS (Apple Silicon) | ✅ Supported |
| iOS | ✅ Supported |
| iPadOS | ✅ Supported |
| Intel Mac | ⚠️ Not tested |
| Windows/Linux | ❌ Not supported |

---

## Requirements

### Hardware

Recommended:

- Apple Silicon Mac (M1/M2/M3/M4)
- iPhone/iPad with Apple Silicon

Minimum:

- 8 GB unified memory

More memory allows:

- larger models
- longer context length
- higher generation limits

---

## Supported Models

LocAI currently supports MLX models.

Examples:

- Llama 3.2 3B Instruct 4-bit
- Qwen 2.5 3B Instruct 4-bit
- Phi-3.5 Mini Instruct 4-bit
- Gemma 2 2B IT 4-bit

Larger models may require devices with more memory.

---

## Architecture

LocAI uses a modular backend architecture that separates the user interface from model execution.