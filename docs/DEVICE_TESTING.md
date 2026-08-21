# Device Testing

Practical notes for building, installing and debugging on real hardware. Simulators and
emulators are not sufficient for this project — inference behavior, memory pressure and
native crashes only show up on device.

**Companions:** [ENGINEERING_NOTES.md](ENGINEERING_NOTES.md) for why the code behaves as it
does · [../STATUS.md](../STATUS.md) for what happened when ·
[../FUTURE_ENHANCEMENTS.md](../FUTURE_ENHANCEMENTS.md) for what's still open.

---

## Known test devices

| Device | Platform | RAM | Notes |
|---|---|---|---|
| iPhone 15 Pro | iOS | 8 GB | Primary iOS device |
| iPad Air (5th gen, M1) | iOS | 8 GB | |
| iPad mini (6th gen) | iOS | 4 GB | Too small for E4B |
| Xiaomi 24030PN60G | Android | — | Primary Android phone; Adreno GPU |
| Lenovo TB336FU | Android 16 | 7.6 GB | MediaTek MT8755, Mali-G57 MC2. Slow — see below |

Device identifiers change per pairing session on iOS. Get the current one with
`xcrun devicectl list devices`.

---

## Android

```bash
adb -s <device-id> install -r app/build/outputs/apk/debug/app-debug.apk
adb -s <device-id> shell am start -n ai.ecoinference.eiapp/ai.ecoinference.app.MainActivity
```

**The launch intent mixes two different names.** The activity class uses the **namespace**
(`ai.ecoinference.app`), not the **applicationId** (`ai.ecoinference.eiapp`). Writing
`ai.ecoinference.eiapp/.MainActivity` fails with "Activity class does not exist".

Gradle needs an explicit JDK:

```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
```

### Useful checks

```bash
# Theme switching for light/dark verification
adb -s <id> shell cmd uimode night no      # light
adb -s <id> shell cmd uimode night yes     # dark
adb -s <id> shell cmd uimode night auto    # restore

# Memory: app footprint and what else is competing
adb -s <id> shell dumpsys meminfo ai.ecoinference.eiapp | grep -E "TOTAL PSS|TOTAL RSS|SWAP"
adb -s <id> shell dumpsys meminfo | sed -n '/Total PSS by process/,/Total PSS by OOM/p'
adb -s <id> shell cat /proc/meminfo | grep -E "MemTotal|MemAvailable|SwapTotal|SwapFree"

# Did the memory killer take something? (check the app's PID first — it may not be the victim)
adb -s <id> shell pidof ai.ecoinference.eiapp
adb -s <id> logcat -d | grep -iE "lowmemorykiller|Killing [0-9]+:"

# Inference benchmark (see below)
adb -s <id> logcat -c && adb -s <id> logcat -d -s "AgentLoop:*" | grep -i benchmark
```

### Benchmark logging

Android had no native benchmark hook (unlike iOS's
`litert_lm_conversation_get_benchmark_info`), so `AgentLoop.kt`'s `runAgentLoop()` wraps the
`chatStream()` collect loop with wall-clock timing and logs
`benchmark: TTFT=… decode=… chunks/s`.

**"Chunks", not tokens** — each streamed emission may be multi-token, so this is a rate
floor, not an exact token count. Clear the buffer (`logcat -c`) first for a clean single-turn
read.

### Verifying a build actually built

Grep the build tool's own literal output before reporting success or handing an APK to
anyone — `BUILD SUCCESSFUL` / `BUILD FAILED` for Gradle, `BUILD SUCCEEDED` / `BUILD FAILED`
for xcodebuild. A task-notification "completed", or an exit-code framing, is **not**
sufficient: a `-q` build can exit non-zero and still produce a notification that reads as
generically done.

This is not hypothetical. A build was once reported clean from a notification while the real
compile had been failing throughout on genuine errors — and the device was then tested against
a **20-hour-stale cached APK** that happened to still be on disk, with no visible error to
anyone until a missing feature was noticed.

**Grepping the marker alone is still not enough.** The cheapest tell that nothing compiled:

> `BUILD SUCCESSFUL in 1s` (anything under ~3 s) immediately after editing a source file means
> Gradle found everything up-to-date and skipped the work. It prints the success marker anyway.

Confirm by comparing the source file's mtime against the compiled `.class` and the output APK,
or force it with `--rerun-tasks`. The same applies to unit tests: `testDebugUnitTest` can
report success **without running a single test** — read the XML in `app/build/test-results/`
and count them.

If something "should be working" after a successful build and isn't, check artifact mtimes
before assuming the bug is in the code.

### Driving the UI over adb

Workable but fiddly. Things that cost time:

- `input text` needs spaces escaped as `%s`; unescaped spaces silently truncate the string.
- Screen coordinates differ between the phone (portrait) and the tablet (landscape,
  2560×1600). Screenshot first, don't reuse coordinates across devices.
- A black screenshot usually means the device dozed, not that the app crashed. Wake with
  `input keyevent KEYCODE_WAKEUP`, and note that a swipe from the top opens the notification
  shade instead of unlocking.
- `install -r` **preserves app data**, so downloaded models survive a reinstall — but it does
  unload the currently-loaded model.

---

## iOS

```bash
xcodebuild -project AIiOS.xcodeproj -scheme AIiOS \
  -destination 'id=<device-id>' -configuration Debug \
  DEVELOPMENT_TEAM=65P94N4JDC build

xcrun devicectl device install app --device <device-id> <path-to-.app>
xcrun devicectl device process launch --device <device-id> ai.ecoinference.eiapp
```

**Simulator builds fail** — the vendored LiteRT-LM `.xcframework`s ship device slices only.
Use `-destination 'generic/platform=iOS'` for a compile check.

### Registering a new device

`-allowProvisioningUpdates` alone does **not** register a brand-new device — it only refreshes
profiles for already-registered ones. You need both flags:

```
-allowProvisioningUpdates -allowProvisioningDeviceRegistration
```

Doing the registration interactively in Xcode's GUI did **not** reliably propagate to what
`xcodebuild` saw. The CLI flag combination is what actually worked.

### Getting logs off a device

`idevicesyslog` and the legacy syslog relay **do not work** on modern iOS — Apple locked it
down. Don't spend time on it again.

Instead, the app redirects native stderr to a file (`AIiOSApp.swift`'s
`redirectNativeStderrToLog()` → `Documents/native_stderr.log`, truncated each launch). It also
writes `ecoinference_debug.log` and `test_failures.log`. Pull them with:

```bash
xcrun devicectl device copy from --device <device-id> \
  --domain-type appDataContainer --domain-identifier ai.ecoinference.eiapp \
  --source /Documents/native_stderr.log --destination ./
```

This was the key tool for diagnosing the iPad blank-screen bug — screenshots and user
descriptions weren't enough.

Other useful `devicectl` subcommands: `info files` (list the app container),
`info processes`, `process signal --pid <n> --signal SIGKILL` for a clean force-quit.

`devicectl device copy to` needs a destination under a real container subfolder — e.g.
`--destination /Documents/foo.litertlm`. The container root (`--destination /foo.litertlm`)
fails with `ERROR: Failed to retrieve the file node … error 7000 (0x1B58)`.

### Simulator: the coordinate-scale trap

Worth its own heading because it has caused a misdiagnosis more than once, in two different
tools.

**Screenshots come back at a different scale than the coordinate space taps use.** The
simulator tooling reports its own coordinate space on attach/launch (e.g. "1032x1376 points")
while handing back a considerably larger image (~1500x2000 for that iPad). Coordinates read
straight off the picture are wrong by a constant factor — about 0.688 in that case.

**Multiply image coordinates by `reported-points-height / image-height` before tapping.**

The failure mode is nasty: a tap lands on the field *below* the one aimed at and typed text
goes into the wrong box, which looks exactly like an app focus bug. The same trap exists in
generic screen-control tooling, where a 750×1622 screenshot corresponds to a 375×812 logical
viewport — a factor of 2.

Two related notes:

- There's no `key` action in the dedicated simulator tool, so there is no cmd+A to clear a
  field. If setup needs text in several fields, it's far quicker to write the app's settings
  file directly into the simulator container
  (`xcrun simctl get_app_container <device> <bundle-id> data`) and relaunch — which exercises
  the real load path anyway.
- Generic `type` actions can trigger iOS's press-and-hold accent popover instead of typing,
  consistently on email and password fields. Writing to the clipboard and pasting with `cmd+v`
  is the reliable route (then approve the paste permission dialog iOS shows once per field).

Flutter's yellow/black "RenderFlex overflowed by N pixels" debug banners render directly into
simulator screenshots, so layout-overflow bugs are just as findable there as in a browser.

---

## Performance reference

Measured on the **Lenovo TB336FU** (Mali-G57 MC2), E2B:

| Backend | TTFT | Decode | App PSS | Device free |
|---|---|---|---|---|
| GPU | 29.7 s | 5.2 chunks/s | 2,589 MB | 2.46 GB |
| CPU | 47.9 s | 5.1 chunks/s | 753 MB | 4.90 GB |

Two separate conclusions, and it's worth keeping them apart:

- **Decode throughput is effectively identical**, so the GPU delegate gives no real decode
  speedup on this chipset. GPU did reach first token sooner.
- **GPU costs ~1.8 GB more RAM**, because weights are copied into GPU memory rather than
  mapped from the model file.

This device is slow on either backend — ~5 chunks/s with a 30–48 s wait is a poor experience
even for the smallest model. The lever is a smaller/quantized model, not backend tuning.

**E4B on this tablet is not viable.** See
[ENGINEERING_NOTES.md §4](ENGINEERING_NOTES.md#4-model-sizing-and-device-capability) — it
loads, but only by evicting the rest of the OS.

---

## On-device test suite

Both mobile apps have **Settings → Developer → Inference Tests**, which runs smoke tests for
inference, Python, cloud, router and vision directly on device.

Two caveats:

1. **A green test screen doesn't mean the feature works.** Both test screens correctly
   prepend the Python location preamble; the chat path didn't, so Python tests passed while
   `use tool` was broken for every location- or time-dependent request.
2. **Some late-run failures are expected on iOS.** Running many Python E2E tests in one pass
   exhausts the real KV-cache (see ENGINEERING_NOTES §2) and a handful start failing partway
   through. The UI says so. This is surfaced deliberately so it isn't mistaken for a
   regression.
