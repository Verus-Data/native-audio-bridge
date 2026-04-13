# Native Audio Bridge

A native macOS voice interaction layer that provides always-on microphone monitoring, hot word detection, speech-to-text transcription, and webhook dispatch for the OpenClaw platform.

## Overview

Native Audio Bridge runs as a lightweight macOS daemon that:

1. Continuously captures microphone input via `AVAudioEngine`
2. Streams audio through `SFSpeechRecognizer` for real-time transcription
3. Detects a configurable hot word (default: "hey claW") using sliding-window pattern matching
4. Captures the spoken command until silence is detected
5. Transcribes and sanitizes the command text
6. Dispatches the command to a configured webhook endpoint (OpenClaw)

### Processing Pipeline

```
Audio Capture → Speech Recognition → Hot Word Detection → Command Buffering → Transcription → Webhook Dispatch
```

### State Machine

```
IDLE → (hot word detected) → LISTENING → (silence timeout) → PROCESSING → DISPATCH → IDLE
```

## Installation

### Prerequisites

- macOS 14.0 (Sonoma) or later
- Xcode 15.0 or later
- Swift 5.9 or later

### Build from Source

```bash
git clone https://github.com/Verus-Data/native-audio-bridge.git
cd native-audio-bridge
swift build -c release
```

The binary will be available at `.build/release/NativeAudioBridge`.

## Usage

### Running

```bash
# Build and run directly
swift run

# Or run the compiled binary
.build/release/NativeAudioBridge
```

The application will:
1. Request microphone and speech recognition permissions
2. Start the audio engine
3. Begin listening for the hot word
4. Press **Ctrl+C** to stop

### Environment Variables

| Variable | Required | Description |
|---|---|---|
| `NATIVE_AUDIO_BRIDGE_TOKEN` | Yes | Bearer token for webhook authentication |
| `NATIVE_AUDIO_BRIDGE_HOT_WORD` | No | Hot word phrase (default: `hey claW`) |
| `NATIVE_AUDIO_BRIDGE_SILENCE_TIMEOUT` | No | Silence duration in ms to end command capture (default: `1500`) |
| `NATIVE_AUDIO_BRIDGE_SILENCE_THRESHOLD` | No | RMS audio level threshold for silence detection (default: `0.01`) |
| `NATIVE_AUDIO_BRIDGE_WEBHOOK_URL` | No | Webhook endpoint URL (default: `https://gateway.openclaw.io/hooks/agent`) |
| `NATIVE_AUDIO_BRIDGE_LOG_LEVEL` | No | Log level: `debug`, `info`, `error` (default: `info`) |

### Example

```bash
export NATIVE_AUDIO_BRIDGE_TOKEN="your-webhook-token-here"
export NATIVE_AUDIO_BRIDGE_WEBHOOK_URL="https://gateway.openclaw.io/hooks/agent"
swift run
```

## Configuration

### Configuration File

A YAML configuration file can be loaded via the `--config` command-line argument:

```bash
swift run NativeAudioBridge --config ~/.native-audio-bridge/config.yaml
```

Example `config.yaml`:

```yaml
hot_word: "hey claW"
silence_timeout: 1500
silence_threshold: 0.01
webhook_url: "https://gateway.openclaw.io/hooks/agent"
webhook_token: "your-token-here"
```

### Priority Order

Configuration values are resolved in this order (highest priority first):

1. Environment variables
2. Configuration file (if provided via `--config`)
3. Default values

### Defaults

| Setting | Default |
|---|---|
| Hot word | `hey claW` |
| Silence timeout | `1500` ms |
| Silence threshold | `0.01` (RMS) |
| Webhook URL | `https://gateway.openclaw.io/hooks/agent` |
| Log level | `info` |

## Architecture

### Core Components

- **AudioEngine** — Manages `AVAudioEngine` for continuous microphone input at 16kHz
- **SpeechRecognizer** — Wraps `SFSpeechRecognizer` for partial and final transcription results
- **HotWordDetector** — Case-insensitive pattern matching with sliding window for wake phrase detection
- **CommandBuffer** — Circular audio buffer with RMS-based silence detection
- **CommandProcessor** — Transcription sanitization and payload preparation
- **WebhookDispatcher** — HTTP POST with exponential backoff retry (3 attempts, 1s/2s/4s delays)
- **StateManager** — Thread-safe finite state machine orchestrating pipeline transitions
- **ConfigurationManager** — Environment variable and config file loading with validation
- **Logger** — Timestamped console output with configurable log levels

### Webhook Payload

```json
{
  "message": "turn on the lights",
  "name": "AudioBridge",
  "agentId": "audio-bridge",
  "wakeMode": "now"
}
```

Authentication is via `Authorization: Bearer <token>` header.

## Development

### Build

```bash
swift build
```

### Run Tests

```bash
swift run NativeAudioBridgeTests
```

### Build for Release

```bash
swift build -c release
```

## License

See [LICENSE](LICENSE) for details.