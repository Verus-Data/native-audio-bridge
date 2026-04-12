# Audio Bridge Implementation Plan

## Phase 1: Core Infrastructure (PR #1)

### Tasks
1. **Create Swift Package structure**
   - Package.swift with AVFoundation, Speech dependencies
   - Main.swift with CLI entry point
   - App.swift with application lifecycle

2. **Implement AudioEngine**
   - AVAudioEngine setup
   - Continuous microphone input tap
   - Audio buffer management (in-memory only)

3. **Implement SpeechRecognizer**
   - SFSpeechRecognizer configuration
   - Partial results handling
   - Continuous recognition

4. **Implement HotWordDetector**
   - Pattern matching for "hey claW" (case-insensitive)
   - Sliding window detection
   - State transition triggering

## Phase 2: Command Processing (PR #2)

### Tasks
1. **Implement CommandBuffer**
   - Circular buffer for command capture
   - Audio level monitoring (RMS)
   - Silence detection (1.5s default)

2. **Implement CommandProcessor**
   - Final STT transcription
   - Text sanitization
   - Dispatch preparation

3. **Implement WebhookDispatcher**
   - HTTP POST to configured endpoint
   - JSON payload formatting
   - Retry logic with exponential backoff
   - Bearer token authentication

## Phase 3: Configuration & Output (PR #3)

### Tasks
1. **Implement ConfigurationManager**
   - YAML config file parsing
   - Default values handling
   - Hot reload support

2. **Implement OutputManager**
   - Webhook output mode
   - JSONL file output mode
   - Switching logic

## Phase 4: Simple Console UI (PR #4)

### Tasks
1. **Implement EventLogger**
   - Console output for hot word detection
   - Command transcription display
   - Webhook dispatch status
   - Error reporting

## Execution Order

| Phase | Component | OpenCode Task | Time Estimate |
|-------|-----------|---------------|---------------|
| 1 | AudioEngine | audio-engine-core | 2h |
| 1 | SpeechRecognizer | speech-recognition | 2h |
| 1 | HotWordDetector | hot-word-detection | 2h |
| 2 | CommandBuffer | command-buffer | 2h |
| 2 | CommandProcessor | command-processor | 2h |
| 2 | WebhookDispatcher | webhook-dispatch | 2h |
| 3 | ConfigurationManager | config-manager | 1h |
| 3 | OutputManager | output-manager | 1h |
| 4 | EventLogger | console-ui | 1h |

## Testing Strategy

- Unit tests for each component
- Integration test for full pipeline
- Manual testing for hot word accuracy
- Performance benchmarking
