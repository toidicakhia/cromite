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
| `18-devtools-popup-caption-strip-fix.patch` | `chrome/browser/ui/views/frame` (1 file) | Don't report caption-button exclusions for popup-type windows with a native frame, removing the unpainted (black) strip below the caption of the undocked DevTools window on pre-Win10. See below. |
| `19-restore-cleartype-font-rendering.patch` | `ui/gfx` (2 files) | Revert the force-grayscale half of cromite's `Do-not-use-Windows-ClearType-Text-Tuner-setting.patch`: honor the system ClearType settings again (stock behavior), removing the soft/washed-out grayscale AA on all text. See below. |
| `20-force-lcd-text-in-renderer.patch` | `third_party/blink` (1 file) | **REVERTED 2026-10-22** (user reported a YouTube problem while testing it; no causal link found; patch kept in `fixups/reverted/`). Force LCD (subpixel/ClearType) text rasterization in every renderer compositor layer (`layers_always_allowed_lcd_text`), so text in floating/composited content (Facebook post dialogs, extension bubbles, animated menus) is no longer rendered with blurry grayscale AA. See below. |
| `21-allow-lcd-text-on-pixel-aligned-layers.patch` | `cc` (1 file) | Allow LCD text when a layer's raster translation is pixel-aligned (`PictureLayerImpl::ComputeLCDTextDisallowedReason`): static `will-change: transform` containers (YouTube sidebar/video titles, Facebook dialogs at rest) lose the grayscale AA without risking the resampling blur that forcing LCD text unconditionally can cause. See below. |
| `22-allow-lcd-text-on-aligned-translucent-layers.patch` | `cc` (1 file) | Keep LCD text on pixel-aligned layers even when the layer background/contents are not opaque (rounded floating panels, extension bubbles, dropdown menus): drop the stock `kBackgroundColorNotOpaque`/`kContentsNotOpaque` fallback for aligned layers, which kept the Proton Pass "Save passkey" bubble on blurry grayscale AA. See below. |

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

### `18-devtools-popup-caption-strip-fix.patch` contents

- On pre-Win10 the tracked delta disables custom-drawn titlebars
  (`ShouldBrowserCustomDrawTitlebar()` returns false) and skips
  `BrowserFrameViewWin::PaintTitlebar()`; windows use the native caption.
- Popup-type windows (undocked DevTools: `TYPE_DEVTOOLS`) are laid out by
  `BrowserViewPopupLayoutImpl::CalculateTopContainerLayout()`, which always
  reserves a top strip from the caption-button exclusions supplied by
  `BrowserFrameViewWin::GetBrowserLayoutParams()`. That strip is painted by
  `PaintTitlebar()` only when the titlebar is custom-drawn, so on pre-Win10
  it stays unpainted; the window contents are transparent on Aero
  (`ShouldWindowContentsBeTransparent()`), and the DWM composites the
  unpainted strip as black.
- Fix: `GetBrowserLayoutParams()` returns no exclusions for popup-type
  windows that use a native frame (`!GetIsNormalType()`, not an opaque hosted
  app frame, `!ShouldBrowserCustomDrawTitlebar()`), so the popup layout no
  longer reserves the strip and the DevTools content starts right below the
  caption.
- Web app windows (`IsOpaqueHostedAppFrame()`, custom-drawn on `< Win10`) and
  normal tabbed windows keep their exclusions (their UI draws in-client
  caption buttons).
- Verified on Win8.1 (undocked DevTools): black strip gone, dock/undock,
  zoom, resize and panel switching behave normally; regular browser windows
  unaffected.

### `19-restore-cleartype-font-rendering.patch` contents

- cromite's `Do-not-use-Windows-ClearType-Text-Tuner-setting.patch` forces
  `SUBPIXEL_RENDERING_NONE` with three `if ((true))` overrides:
  an early return in `GetSubpixelRenderingGeometry()`, an early return in
  `FontUtilWin::GetTextSettingsRegistryKey()`, and an unconditional branch in
  `CachedFontRenderParams::GetParams()` that ignores
  `SystemParametersInfo(SPI_GETFONTSMOOTHING)`.
- Blink renderers drive their font style from the browser's
  `gfx::FontRenderParams`: `renderer_preferences_.subpixel_rendering`
  (`WebViewImpl::UpdateFontRenderingFromRendererPrefs()`) →
  `WebFontRendering::SetLCDTextEnabled()` → `FontCache::lcd_text_enabled_` →
  `FontPlatformData::QuerySystemForRenderStyle()` →
  `CreateSkFont()` sets `kSubpixelAntiAlias` only if subpixel rendering is
  not NONE. With the forced NONE every glyph is drawn with grayscale AA, so
  on ClearType-enabled systems (the Win7/8/8.1 default) all browser UI and
  web content text is perceptibly softer than stock Chrome (user report: the
  text inside the Facebook post dialog on Win8.1 looked blurry; screenshot
  forensics: all glyph pixels are channel-neutral, i.e. no ClearType
  fringes).
- Fix: drop the three `if ((true))` overrides. `GetParams()` honors
  `SPI_GETFONTSMOOTHING` + `SPI_GETFONTSMOOTHINGTYPE` (ClearType) again,
  `GetSubpixelRenderingGeometry()` reads the per-display
  `PixelStructure`/`SPI_GETFONTSMOOTHINGORIENTATION` registry values, and
  `GetTextSettingsRegistryKey()` is re-enabled (also restores the ClearType
  tuner gamma/contrast read via `kUseGammaContrastRegistrySettings`). The
  win7 patchset's `win::IsDirectWriteEnabled()` tweak in the same block is
  kept (GDI fallback on Win7 stays without subpixel positioning).
- Trade-off: re-enables the ClearType-tuner fingerprint bits cromite
  deliberately hides (subpixel geometry orientation, text gamma/contrast).
  To go back to cromite behavior, drop this fixup; there is no flag.

### `20-force-lcd-text-in-renderer.patch` contents

> **REVERTED (2026-10-22).** The user reported a YouTube problem shortly after
> installing the build with this fixup and asked to revert it and audit the
> patchset. No mechanism connecting a text-rasterization flag to media
> playback was found; the build was reverted to be safe
> (`git revert e912407f39`, patch moved to `fixups/reverted/`). Move the patch
> back into `fixups/` to re-enable it once the YouTube issue is understood.
> All findings below remain valid.

- After fixup 19 the general ClearType rendering was restored, but text in
  floating/composited web content still rendered with grayscale AA. cc
  disallows LCD text per layer in the renderer:
  `PictureLayerImpl::ComputeLCDTextDisallowedReason()` returns
  `kWillChangeTransform`, `kTransformAnimation`, `kPixelOrColorEffect`
  (`filter`/`backdrop-filter`), `kNonIntegral*` or `kContentsNotOpaque` for
  any layer whose contents may be resampled or drawn over a non-opaque
  backdrop. Facebook's post dialog qualifies on several counts (entrance
  `transform` animation, `will-change: transform`, `translate(-50%,-50%)`
  centering with fractional offsets, backdrop-blurred overlay), so the whole
  dialog subtree — title, caption, comments, composer — rasterizes grayscale.
  This is stock Chromium behavior (Chrome/Edge render such text the same),
  but on this build the contrast with the now-ClearType-rendered "normal"
  text is very visible, and the user prefers crisp text.
- Fix: set `settings.layers_always_allowed_lcd_text = true` in
  `blink::GenerateLayerTreeSettings()` (renderer web-content settings). The
  browser UI compositor already does exactly this
  (`ui/compositor/compositor.cc`), which is why the omnibox/tab-strip text
  had ClearType fringes all along; this extends the same behavior to web
  content. Every text layer then rasterizes with subpixel AA regardless of
  transform/opacity/backdrop conditions.
- Verified empirically with a test page (`artifacts/final/text-test.html`):
  panel A (plain text) and the toolbar tab title show ClearType fringes
  (channel deltas ±179), while a card over a `backdrop-filter` background, a
  `will-change: transform` card, an `opacity: .999` card and a `scale(1.001)`
  card were all channel-neutral (pure grayscale) in the same screenshot —
  the exact signature of the Facebook dialog text.
- Trade-off: such layers may be composited with fractional offsets or
  resampled (during scale animations), which can show faint color fringing on
  text while a dialog animates; where Chromium previously chose safety over
  sharpness. To go back to stock behavior, drop this fixup (or restore the
  `chrome-baseline-fixup19.dll` artifact baked before it); there is no flag.

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

### `21-allow-lcd-text-on-pixel-aligned-layers.patch` contents

- User follow-up after the fixup-20 revert: with fixup 20 (or 19) build, the
  text of YouTube's sidebar and video titles still renders with grayscale AA
  (measured on the user's screenshot: those regions are channel-neutral while
  the search box / metadata lines have ClearType fringes). These elements sit
  in `will-change: transform` containers, so `ComputeLCDTextDisallowedReason()`
  returns `kWillChangeTransform` even though nothing is animating and the
  layer is rastered pixel-exact.
- Forcing LCD text for *all* layers (fixup 20) is too blunt: layers that are
  actually resampled (transform animations, fractional offsets, filters) then
  got sampled subpixel glyphs and looked blurry/noisy (the YouTube regression
  the user hit). This patch instead reorders the checks: `kTransformAnimation`
  stays unconditional; the will-change / effect-filter / fractional-offset
  checks only apply when `raster_translation_aligns_pixels` is false. Layers
  whose raster translation is pixel-aligned are drawn 1:1, so subpixel glyphs
  cannot smear — they can safely use LCD text. Non-aligned layers keep the
  stock grayscale pipeline, so the fixup-20 artifacts cannot come back.
- Expected effects: static `will-change` containers (YouTube sidebar/titles,
  Facebook dialogs at rest, extension bubbles) get ClearType; running
  animations and non-opaque/scaled content stay grayscale.
- Trade-off: during a purely translational animation the raster translation
  can remain aligned, so LCD text may persist while the layer moves (Chromium
  snaps the composited position to whole pixels; stock behavior would have
  switched to grayscale). To go back to stock, drop this fixup.

### `22-allow-lcd-text-on-aligned-translucent-layers.patch` contents

- User follow-up after fixup 21 (screenshot of the Proton Pass "Save passkey"
  bubble): every text run in the bubble measures as pure grayscale AA (100%
  of the text pixels lie on the alpha-blend line between the text color and
  the card background; zero subpixel deviation). The bubble is a rounded
  floating panel whose background/contents are not opaque, so
  `ComputeLCDTextDisallowedReason()` still returns
  `kBackgroundColorNotOpaque`/`kContentsNotOpaque` even though the layer is
  rastered pixel-aligned and nothing animates.
- This patch drops that fallback for aligned layers: a pixel-aligned layer is
  composited 1:1, so per-subpixel glyph blending stays pixel-exact even when
  the surrounding pixels are translucent — the glyph edges blend per-subpixel
  against transparency exactly like classic ClearType. Non-aligned layers
  (fractional offsets, running animations, pending will-change) still return
  grayscale before this check, so the fixup-20 resampling blur cannot come
  back.
- Expected effects: text on rounded/translucent floating panels (extension
  bubbles, dropdown menus, dialogs) gets ClearType again. Trade-off: such
  text now shows normal colored ClearType fringes over variegated backdrops;
  if a specific panel looks worse than the grayscale AA, drop this fixup.
- Diagnostic value: if the bubble is still grayscale after this fixup, its
  layer is not pixel-aligned (fractional position or animation), and only a
  runtime probe of the disallow reason can tell us why.
