# Native Audio Bridge - Product Requirements Document

**Project:** native-audio-bridge  
**Status:** Planning  
**Author:** Zack (Developer Agent)  
**Date:** 2026-04-12  

---

## Overview

A native macOS voice interaction layer that provides always-on hot word detection, speech-to-text, and text-to-speech capabilities. Audio is processed entirely in memory with no persistent storage, ensuring privacy. Commands detected after the hot word are sent via webhook for action or logged for conversation.

---

## Goals

1. **Always-on listening** - Continuous microphone monitoring for hot word detection
2. **Privacy-first** - All audio processing in memory, no disk persistence
3. **Native macOS** - Built with Swift using Apple's native frameworks
4. **Dual output modes** - Conversation logging and targeted action via webhook
5. **Fast response** - Webhook integration for real-time command processing

---

## Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────────┐
│                     Audio Bridge (Swift)                    │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │   Hot Word   │    │   Command    │    │     TTS      │  │
│  │   Detector   │───▶│   Processor  │───▶│   Output     │  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
│          │                   │                   │          │
│          ▼                   ▼                   ▼          │
│  ┌──────────────────────────────────────────────────────┐ │
│  │              AVAudioEngine (In-Memory)                 │ │
│  └──────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │  OpenClaw Webhook │
                    └──────────────────┘
```

### Data Flow

1. **Always-On Mic** → AVAudioEngine captures continuous audio
2. **Hot Word Detection** → SFSpeechRecognizer streams partial results, pattern matches wake word
3. **Command Capture** → After hot word, buffer audio until silence detected
4. **STT Processing** → Final transcription via SFSpeechRecognizer (fallback: WhisperKit)
5. **Output Dispatch** → Webhook to OpenClaw OR local conversation log
6. **TTS Response** → NSSpeechSynthesizer for audio feedback

---

## Requirements

### Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| F1 | Continuous microphone monitoring without key presses | P0 |
| F2 | Hot word detection in audio stream (not predefined list) | P0 |
| F3 | Command capture after hot word until silence | P0 |
| F4 | In-memory audio processing only - no disk persistence | P0 |
| F5 | Webhook dispatch for targeted actions | P0 |
| F6 | Local conversation log mode | P1 |
| F7 | TTS output to speakers and file | P1 |
| F8 | Silence detection with configurable timeout | P1 |

### Non-Functional Requirements

| ID | Requirement | Target |
|----|-------------|--------|
| NF1 | Hot word detection latency | < 500ms |
| NF2 | Command transcription accuracy | > 95% |
| NF3 | Memory footprint | < 100MB |
| NF4 | CPU usage (idle) | < 5% |
| NF5 | Privacy - no audio to disk | Enforced |

### Technical Requirements

- **Language:** Swift
- **Minimum macOS:** 14.0 (Sonoma)
- **Frameworks:** AVFoundation, Speech, AppKit
- **Architecture:** Apple Silicon optimized
- **Dependencies:** None (built-in frameworks only, optional WhisperKit)

---

## State Machine

```
┌─────────┐     Hot Word      ┌──────────┐     Silence      ┌─────────┐
│  IDLE   │ ─────────────────▶│ LISTENING│ ────────────────▶│ PROCESS │
│ (Always │    Detected       │(Capture  │    Detected      │ (STT)   │
│   On)   │                   │ Command) │                  │         │
└─────────┘                   └──────────┘                  └────┬────┘
     ▲                                                          │
     │                                                          ▼
     │                                                    ┌─────────┐
     │                                                    │ DISPATCH│
     │                                                    │(Webhook │
     │                                                    │ or Log) │
     │                                                    └────┬────┘
     │                                                         │
     └─────────────────────────────────────────────────────────┘
                            TTS Response (if any)
```

---

## Implementation Phases

### Phase 1: Core Audio Pipeline (MVP)
- [ ] AVAudioEngine continuous mic capture
- [ ] SFSpeechRecognizer integration
- [ ] Hot word pattern detection
- [ ] Command capture with silence detection
- [ ] In-memory-only enforcement

### Phase 2: Output & Integration
- [ ] Webhook dispatch to OpenClaw
- [ ] Conversation log mode
- [ ] Configuration (hot word, silence threshold)

### Phase 3: TTS & Polish
- [ ] NSSpeechSynthesizer integration
- [ ] File output for Telegram/audio channels
- [ ] Menu bar UI for settings
- [ ] Optional WhisperKit fallback

### Phase 4: Advanced Features
- [ ] Audio file input processing
- [ ] Custom voice selection
- [ ] Multiple hot words
- [ ] Background noise filtering

---

## Open Questions

1. **Hot word:** What should the wake phrase be? (e.g., "Hey Claw", "OK Zack")
2. **Silence threshold:** How long of silence ends command? (default: 1.5s)
3. **Webhook endpoint:** What URL should commands POST to?
4. **Conversation log:** Format and location for local transcripts?

---

## References

- [SFSpeechRecognizer Documentation](https://developer.apple.com/documentation/speech/sfspeechrecognizer)
- [AVAudioEngine Documentation](https://developer.apple.com/documentation/avfaudio/avaudioengine)
- [NSSpeechSynthesizer Documentation](https://developer.apple.com/documentation/appkit/nsspeechsynthesizer)
- Similar projects: OpenDictation, Speak2, Pindrop, KeyVox

---

_This PRD is a living document. Updates to follow as implementation progresses._
