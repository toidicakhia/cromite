# Win7 runtime fixes (post-REWORK audit)

Fixes for runtime bugs found by auditing this patchset against the M153
sources after the full series is applied. They are additional to the
original 335 REWORK entries and are applied automatically at the **end of
phase 3** by `04b-apply-win7-patches.sh` (each patch is guarded with
`git apply --check`, so a patch that no longer applies is skipped instead
of breaking the pipeline).

Canonical, build-verified state: `chromium/src` branch
`win7-153.0.8010.37` with these fixes applied on top of the REWORK
patches. All affected objects compile (`siso ninja -C out/win64 chrome`);
`chrome.exe` builds and links.

## Patches

| Patch | Scope | Summary |
|---|---|---|
| `10-win7-runtime-fixes.patch` | tracked MCP sources (26 files) | See list below. |
| `11-dawn-downlevel-kernelbase.patch` | `third_party/dawn` | Treat a missing `CompareObjectHandles` (Win7/8) as optional; null-check it in `SharedFenceD3D11`. |
| `12-webrtc-win7-desktop-capture.patch` | `third_party/webrtc` | `Shcore.dll` fallback is not reachable when the DLL is missing; fix DPI fallback path. `GetModuleFileNameEx` returns a NUL-terminated string (do not use `path_len`). |
| `13-tls-aes-hw-preference.patch` | `net`, `net/third_party/quiche` (submodule), `cromite_flags` | Always announce the hardware-AES TLS/QUIC cipher preference and disable the cromite "no hw aes" warning by default. See below. |
| `14-enable-jit-webassembly.patch` | `components/content_settings` (1 file) | Re-enable the JavaScript JIT content setting by default (stock Chrome behavior) so WebAssembly works. See below. |
| `15-disable-desktop-60hz-frame-throttle.patch` | `cc/base` (1 file) | Default `kThrottleMainFrameTo60Hz` to disabled on desktop, so cromite no longer appends `--disable-frame-rate-limit` (GPU starvation on old hardware). See below. |
| `16-suppress-unsupported-os-warning.patch` | `chrome/browser/ui/startup` (1 file) | Default the `browser.suppress_unsupported_os_warning` pref to `true`, hiding the "To get future Cromite updates, you'll need Windows 10 or later" infobar on Win7/8/8.1. See below. |
| `17-viewport-protection-hittest-fix.patch` | `third_party/blink` (1 file) | Map DIP coordinates by the device-emulation scale in the OOPIF hit test (`GetFrameSinkIdAtPoint`), so clicks land on cross-origin iframes (Proton Pass popup) while cromite's Viewport Protection is active. See below. |

### `13-tls-aes-hw-preference.patch` contents

- **net**: the shared client `SSL_CTX` in `ssl_client_socket_impl.cc`
  (TCP TLS, DoH, WebSockets, proxies) calls
  `bssl::SSL_CTX_set_aes_hw_override_for_testing(ctx, true)`, so the TLS 1.3
  cipher list and the ECH GREASE configuration always match AES-capable
  devices instead of revealing missing AES-NI support (cromite's patch
  description: "an additional fingerprint bit").
- **quiche** (submodule, worktree-only): same override for the QUIC
  `TlsConnection::CreateSslCtx()`; `QuicCryptoClientConfig::SetDefaults()`
  unconditionally prefers `{kAESG, kCC20}` for legacy GQUIC.
- **cromite_flags**: `kNoAESHardwareMessage` is
  `FEATURE_DISABLED_BY_DEFAULT` (the "Your device does not support hardware
  aes, so it is easier to track you at the network level" infobar no longer
  shows; can be re-enabled from `chrome://flags/#no-hw-aes-warning`).
- Trade-off: on CPUs/VMs without AES-NI the TLS bulk encryption keeps using
  BoringSSL's software AES (slower than ChaCha20, which BoringSSL would
  otherwise prefer); only the advertised preference changes. The alternative
  is a network-level fingerprint bit.

### `14-enable-jit-webassembly.patch` contents

- cromite's `JIT-site-settings.patch` registers the `JAVASCRIPT_JIT` content
  setting with `CONTENT_SETTING_BLOCK` as its default ("disabled by default").
  `RenderProcessHostImpl::AppendRendererCommandLine` then adds `--jitless` to
  `--js-flags` for every renderer, and V8's `--jitless` implies
  `--wasm-jitless` (`DEFINE_IMPLICATION(jitless, wasm_jitless)` in
  `v8/src/flags/flag-definitions.h`); the jitless WebAssembly interpreter
  (DRUMBRAKE) is not built in Chromium, so `WebAssembly` is not exposed at all.
  Web apps that hard-require WASM (e.g. Proton Pass: "Your browser ...
  WebAssembly: Please update to a modern browser with WASM support") break.
- The fix flips the registry default back to `CONTENT_SETTING_ALLOW` (stock
  Chrome behavior). The setting remains functional: individual sites can still
  be blocked (renderer gets `--jitless` for them) from the site settings UI.
- Trade-off: this restores the stock JIT attack surface that cromite
  deliberately removes by default; WebAssembly cannot work without JIT.

### `15-disable-desktop-60hz-frame-throttle.patch` contents

- cromite's `Set-the-screen-frame-rate-to-60-Hz.patch` defines
  `kThrottleMainFrameTo60Hz` with `CROMITE_FEATURE(..., FEATURE_ENABLED_BY_DEFAULT)`
  on every platform, and `ChromeContentBrowserClient::AppendExtraCommandLineSwitches`
  (non-Android) then appends `--disable-frame-rate-limit` to the browser
  command line. The switch removes the compositor's internal frame limit on
  the browser, GPU and renderer processes (`gpu_process_host.cc`,
  `ui/compositor/compositor.cc`, `viz_process_transport_factory.cc`).
- On old GPUs (verified on Intel Ironlake + 2011 driver, Windows 8.1) this
  saturates the GPU: heavy pages lag and animated overlays (e.g. Google's
  account chooser) hang the whole UI. It also delays input processing.
- The fix flips the feature default to `FEATURE_DISABLED_BY_DEFAULT` on
  desktop (restores upstream desktop behavior). Users can still opt in via
  `chrome://flags/#throttle-main-thread-to-60hz`.

### `16-suppress-unsupported-os-warning.patch` contents

- `StartupBrowserCreator::RegisterLocalStatePrefs()` registers
  `browser.suppress_unsupported_os_warning` with a default of `false`; on
  Windows 7/8/8.1 (`ObsoleteSystem::IsObsoleteNowOrSoon()` +
  `IsEndOfTheLine()`), `infobar_utils.cc` therefore shows the upstream
  "To get future Cromite updates, you'll need Windows 10 or later" infobar at
  every startup.
- The fix defaults the pref to `true`, i.e. always suppressed on this fork.
  This is the same switch the `SuppressUnsupportedOSWarning` enterprise policy
  controls, so policy can still turn the infobar back on.
- Note: the pref is stored in `Local State`
  (`browser.suppress_unsupported_os_warning`); if a profile already has it set
  to `false`, it wins over the default (set/remove it while the browser is
  closed, or via policy).

### `17-viewport-protection-hittest-fix.patch` contents

- Cromite's Viewport Protection (blink `kViewportProtection`, enabled by
  default) runs the tab through `ScreenMetricsEmulator` with a random scale
  per origin/navigation (`page.cc: CalculateEmulatedScreenSetting`, observed
  1.0022–1.0105): the widget's Blink space is enlarged by `1/scale` while the
  compositor draws everything scaled back down by `scale`.
- `WebFrameWidgetImpl::GetFrameSinkIdAtPoint()` hit-tested the raw DIP point
  in that enlarged space, so the local point reported for a cross-origin
  iframe was off by `position * (1 - 1/scale)` (measured ~2.7 px at x≈1350 for
  scale 1.0022, ~11 px for scale 1.009).
- The browser cross-checks the reply against its own viz transform
  (`RenderWidgetTargeter`, 2 px epsilon) and drops the target on mismatch, so
  clicks on the iframe fell through to the parent document (Proton Pass popup
  unclickable).
- Fix: scale the hit test point by `1/emulation_scale` when `DeviceEmulator()`
  is active, matching `ScreenMetricsEmulator::Apply()`. Verified with
  instrumented GEOM/REPLY logs (`resolved=CHILD final=CHILD`) and on the live
  popup; Viewport Protection itself keeps working as before.

### `10-win7-runtime-fixes.patch` contents

- **sandbox/win**: assign the job object after process creation on
  `< Win8` (`CREATE_BREAKAWAY_FROM_JOB` + `AssignProcessToJobObject`,
  `SBOX_ERROR_ASSIGN_PROCESS_TO_JOB_OBJECT`); fix job handle lifetime;
  close Win7 handles from the enumerated process handle map; drop the
  unconditional `EnumSystemLocalesEx` call; do **not** close
  `\Device\KsecDD` on `< Win10` (cryptbase uses that handle for
  `RtlGenRandom`; without `ProcessPrng`, BoringSSL aborts on entropy
  failure and the renderer dies with "Aw, Snap!").
- **base/win**: `HStringCompare` failure no longer leaves `*result`
  uninitialized (`DCHECK` was compiled out in release); `RunDeElevated`
  no longer returns an empty `Process` on failure; `GetModuleFileNameEx`
  callers grant `PROCESS_VM_READ`.
- **base/time**: `LiveTicksNowIgnoringOverride` forces the QPC globals
  initialization (`TimeTicks::IsHighResolution()`) and falls back to
  `GetTickCount64` when QPC is unusable, instead of dividing by zero.
- **net/ssl**: initialize `ncrypt_get_property_` to `nullptr`.
- **media/audio**: `WIM_DATA` uses `dwBytesRecorded` (clamped to the
  AudioBus) instead of the full buffer; fix buffer lifetime in
  `Start()`/`Close()`.
- **gpu / content**: allow the ANGLE D3D9 fallback on `< Win10`; use
  SwANGLE (not legacy SwiftShader GL) for software WebGL; restore
  `EnableIntelShaderCache()`.
- **device/bluetooth**: treat Windows 7 as Bluetooth-capable (classic
  adapter path).
- **components/os_crypt, components/device_signals, chrome, remoting,
  crashpad**: win7 branch fixes (see commit/diff for details).

## Applying manually

If a patch was skipped (`git apply --check` failed because the tree drifted),
apply with 3-way merge:

```bash
git -C "$CHROMIUM_SRC" apply --3way \
    "$WIN7_PATCHSET_DIR/overrides/deps/fixups/10-win7-runtime-fixes.patch"
```

For `11-*`/`12-*` run the same command from `third_party/dawn` /
`third_party/webrtc` respectively using `-p1` (paths include the
`third_party/<repo>/` prefix, so apply from `chromium/src` or strip one
level).
