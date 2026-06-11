# Android Testing

## Primary Emulator

Use the Pixel 9 Pro API 36 Google APIs AVD for parity testing:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" @EclipsePixel9ProApi36 -gpu auto
```

If the emulator window or player surface is black, restart it with software graphics:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" @EclipsePixel9ProApi36 -gpu swiftshader_indirect
```

For a clean boot when snapshots get stale:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" @EclipsePixel9ProApi36 -no-snapshot-load -gpu auto
```

The expected AVD profile is:

- Device: Pixel 9 Pro
- Image: `system-images;android-36;google_apis;x86_64`
- RAM: 6 GB
- Data partition: 12 GB
- Keyboard: enabled
- Graphics: `auto` first, `swiftshader_indirect` fallback

## Build Gate

Run the Android verification lane from `android`:

```powershell
.\gradlew.bat testDebugUnitTest assembleDebug lintDebug
```

## Emulator Smoke

Install the debug APK and cover these flows before release:

- Home catalog loading, hero behavior, search, detail, library, schedule, settings, backup restore, and release prompt checks.
- Services and Stremio install/update/enable/order, progressive search/detail/episode/stream resolution, source health, and log export/clear.
- MPV playback for direct HTTP(S), HLS, redirected streams, custom headers, external ASS/SRT/VTT subtitles, audio/subtitle track switching, local downloads, PiP, rotation, background/resume, skip segments, next episode, episode browser, finish sync, and tracker sync.
- Media and reader downloads: pause, resume, delete, offline restore, and app-scoped storage cleanup.
- Manga and novel sources: portable Kanzen module install/update/search/detail/chapter/page loading, reader progress, collections, cache, downloads, and restored iOS Aidoku sources shown as unavailable when non-portable.
