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
