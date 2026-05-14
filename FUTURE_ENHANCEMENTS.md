# Future Enhancements

## Morse Code Receiver Screen
Receive and decode Morse code signals from another phone's torch via the camera.

**Approach:**
- `camera` plugin streams `CameraImage` frames at 30fps
- Average Y-channel luminance per frame to detect torch ON/OFF transitions
- Lock camera exposure (`ExposureMode.locked`) to prevent auto-exposure shifting the baseline
- Relative threshold (luma > mean + N×stddev) handles varying ambient light
- Calibrate unit length from the first received dot (or assume 200ms since both devices run same app)
- Classify durations: < 1.5× unit = dot, ≥ 1.5× unit = dash; < 2× unit = symbol gap, ≥ 2× = letter gap
- Full Morse-to-text lookup table for decoding

**UI:** Dedicated MorseReceiverScreen (not an LLM tool) with live camera preview,
luminance waveform visualisation, and decoded text appearing in real time.

**Depends on:** `camera` plugin (not yet in pubspec.yaml)

---
