# Kế hoạch: thêm hỗ trợ Windows 7/8/8.1 vào build Cromite 153.0.8010.37

Trạng thái: **BUILD XONG — `artifacts/chrome-win7.zip` sẵn sàng test** — ngày 2026-10-20 (xem §8)
Nguồn patch: https://github.com/e3kskoy7wqk/Chromium-for-windows-7-REWORK (dir `chromium-153.0.8010.27`)
Build nền: `~/cromite-build` (Cromite 153.0.8010.37, cross-compile Linux → win64, đã xong `chrome-win.zip`)

## 1. Mục tiêu & phạm vi

- Thêm bộ patches re-add codepath Windows 7 (đã bị upstream xóa từ M110+) vào build cromite, để
  `chrome-win.zip` chạy được trên **Windows 7 SP1 x64 / 8 / 8.1**.
- **Không** hỗ trợ XP/Vista (né được toàn bộ phần SDK 22621 UCRT downgrade + VS2019 + che VS2022).
- Giữ build hiện tại (Win10+) nguyên vẹn: win7 là **opt-in** (`WITH_WIN7=1`), không đổi default.

## 2. Đặc điểm bộ patch (đã khảo sát)

- 336 entry trong `commit_hashes.txt` = 333 diff upstream re-add + 3 file đặc biệt
  (`rust01.diff`, `rust02.diff`, `cdm_module.cc_corrected.diff`).
- ~1575 file, ~317k dòng diff (13 MB): lớn nhưng chủ yếu là fallback cơ học
  (`GetProcAddress` + delay-load cho API chỉ có trên Vista/8/10), ví dụ:
  - `base/win/*` (windows_version, hstring, core_winrt, registry…)
  - `sandbox/win/*`, `ui/gl`, `ui/base`, `ui/views`, `gpu/*`, `media/gpu`
  - `third_party/angle` (~170 file, re-add ~780 dòng D3D9), `third_party/swiftshader` (marl fiber fallback)
  - `third_party/libwebp` thread_utils (condvar fallback), `mojo/core` (named pipe/condvar win7)
  - `build/config/win/BUILD.gn`: bỏ `-msse3` (hạ yêu cầu CPU về SSE2) + `chrome/installer` check SSE2
- `rust01/rust02`: patch **source std/backtrace của rust-toolchain** (`third_party/rust-toolchain/lib/rustlib/src/rust/...`),
  chuyển các module `windows7.rs` (Condvar/Mutex/Parker) thành **unconditional cho `target_os = "windows"`**.
  Chromium build std từ source (`//build/rust/std`) nên patch này có hiệu lực khi build lại.
- `cdm_module.cc_corrected.diff`: fallback cho Widevine/CDM (chỉ có tác dụng nếu `enable_widevine=true`; cromite
  không bật → inert, có thể apply cho đồng bộ hoặc skip).
- Thứ tự apply của tác giả (`apply_patches.bat`): **reverse `commit_hashes.txt`** = cũ → mới; 333 diff trước,
  rồi `cdm`, `rust01`, `rust02` cuối cùng. Dùng `git apply --check` + `--ignore-space-change`.

## 3. Đối chiếu môi trường ta vs tác giả

| Yếu tố | Tác giả (Windows native) | Ta (Linux cross) | Hành động |
|---|---|---|---|
| SDK | 22621 + 26100 (+VS2022) | 28000 (đã cài, build OK) | Giữ 28000 để build; thêm **26100 chỉ để lấy d3dcompiler_47.dll** |
| VS | 2022 18.x | MSVC 14.50.18 (msvc-wine) | Giữ nguyên |
| `treat_warnings_as_errors` | **false (bắt buộc)** | cromite đặt `true` | Override `false` khi `WITH_WIN7=1` |
| `is_component_build` / `is_debug` / `is_official_build` | false/false/true | giống | OK |
| PGO | họ thường `chrome_pgo_phase=0` | cromite `=2` | Thử `2` trước; fallback `0` nếu lỗi |
| `enable_nacl=false` | họ set | 153 đã bỏ NaCl, default OK | Bỏ qua |
| `use_static_angle` | `false` | hiện đã dynamic (`libEGL/libGLESv2.dll` trong zip) | OK |
| Widevine | bật | cromite tắt | Giữ tắt; cdm patch inert |
| Version patch | 153.0.8010.**27** | 153.0.8010.**37** | Lệch 10 build fix → cần adapt một số diff |

## 4. Phương án kỹ thuật

### 4.1 Import patch set vào repo (versioned, tái lập được)

- Tạo `build/win7-patches/153.0.8010.27/` chứa nguyên trạng: 333 `*.diff`, `rust01.diff`, `rust02.diff`,
  `cdm_module.cc_corrected.diff`, `commit_hashes.txt`, `commit_message_*.txt`.
- Danh sách `build/win7_patches_list.txt` (thứ tự apply chuẩn = reverse `commit_hashes.txt`).
- KHÔNG sửa nội dung diff gốc; mọi adaptation cho .37 nằm ở file override riêng
  (`overrides/<hash>.patch` hoặc `overrides/<hash>.sed`) + log lý do, để dễ rebase khi họ ra bản mới.

### 4.2 Script áp dụng

- Script mới `scripts/04b-apply-win7-patches.sh`:
  1. Chỉ chạy khi `WITH_WIN7=1`.
  2. Marker resume: `<src>/.win7_patches_applied` (giống pattern `.cromite_patches_applied`); hỗ trợ chạy lại sau reboot.
  3. Trước khi apply: `git fetch --depth 1 origin refs/tags/153.0.8010.27` **nếu chưa có** — đưa blob vanilla .27
     vào object DB để `git apply --3way` merge sạch phần lệch .27→.37.
  4. Loop 336 entry: `git apply --3way --ignore-space-change` (check trước); nếu fail → áp override nếu có,
     ngược lại log vào `logs/w7-patch-failures.txt` và **dừng** (không apply mù).
     Sau mỗi patch: commit với `commit_message_<hash>.txt` (giữ history như upstream, dễ bisect).
  5. Ghi `HEAD` + số patch vào marker.
- Thứ tự pipeline: `03 fetch` → `04 cromite patches` → **`04b win7`** → `06/07 gn` → `08 build` → `09 package`.
- Cảnh báo: `rust-toolchain` là gclient dep — nếu 03 re-sync, patch rust mất; luôn chạy 04b sau 03.
  Revision rust-toolchain giữa .27/.37 có thể lệch → nếu `rust0*.diff` fail context thì adapt thủ công.

### 4.3 gn args khi `WITH_WIN7=1`

Thêm block override trong `07-gn.sh` (append vào args):
```
treat_warnings_as_errors = false   # bắt buộc theo tác giả
# chrome_pgo_phase: giữ 2; nếu fail/dị thường đổi 0
```
- Không cần đổi `is_official_build/is_debug/is_component_build/proprietary_codecs/ffmpeg_branding` (đã đúng).
- `-msse3` bị bỏ bởi chính patch `build/config/win/BUILD.gn` (không cần cờ gn).

### 4.4 Packaging

- `d3dcompiler_47.dll`: dùng bản **SDK 26100** thay vì 28000 (theo README dự án) — tải thêm component
  `Microsoft.VisualStudio.Component.Windows11SDK.26100` bằng `vsdownload.py` (chỉ Redist), cache riêng
  `win_sdk/sdks/26100-redist/`. Sửa `09-package.sh`: nếu `WITH_WIN7=1` lấy từ đó, output `chrome-win7.zip`.
- Các DLL khác giữ nguyên (`libEGL/libGLESv2/vulkan-1/d3dcompiler_47` đều đã có trong zip).

### 4.5 Kiểm thử

1. **Static (bắt buộc):** `llvm-objdump -p` / `pefile` liệt kê import của `chrome.exe`, `chrome.dll`,
   `libGLESv2.dll`, `libEGL.dll`; diff trước/sau patch; xác nhận không còn import trực tiếp các API
   Win8/10-only (WaitOnAddress, ProcessPrng, GetSystemTimePreciseAsFileTime, CreateFile2, …)
   trừ khi có fallback runtime. Có thể so với danh sách export của kernel32/advapi32 Win7 SP1.
2. **Rebuild sạch:** patches chạm ~1575 file → rebuild lớn (~2–4h, siso `--offline` như cũ). Lặp fix compile
   (warnings đã off nên chủ yếu là lỗi thật + conflict gn).
3. **Runtime (nếu có VM):** QEMU/KVM Win7 SP1 x64 → smoke test (`--no-sandbox --disable-gpu`, render test,
   youtube, about:gpu). Không có Win7 máy thật → ghi rõ trong README là "untested on real Win7" hoặc mượn
   kết quả cộng đồng (họ đã test .27 chạy Win7).
4. **Không hồi quy build thường:** build default (WITH_WIN7=0) phải vẫn ra `chrome-win.zip` như hiện tại.

## 5. Rủi ro & đối phó

| Rủi ro | Mức | Đối phó |
|---|---|---|
| 70 file overlap giữa w7 patches và 327 cromite patches → conflict | Cao | `git apply --3way` (blob vanilla có sẵn sau fetch .27) + resolve tay giữ hành vi cromite; log từng conflict |
| .27 → .37 lệch 10 build fixes | Cao | 3-way trước; hunk fail → so `git diff 153.0.8010.27 153.0.8010.37 -- <file>` rồi rebase tay |
| Rust toolchain revision lệch giữa .27/.37 | TB | Nếu fail: adapt theo source thực tế (rust01/rust02 nhỏ, 5 file); hoặc pin rust-toolchain revision của .27 (nếu tương thích) |
| Warnings biến thành lỗi | Chắc chắn | `treat_warnings_as_errors=false` |
| PGO profile mismatch/oddities | TB | giữ `chrome_pgo_phase=2`; fallback 0 (mất ~5–10% perf) |
| UCRT SDK 28000 dùng API mới hơn Win7 | TB | Win7 SP1 có UCRT qua KB2999226; nếu binary fail load → thử libs 26100 (không cần headers) hoặc patch riêng; đây là rủi ro duy nhất thực sự mới so với config tác giả |
| GPU/ANGLE/D3D9 trên Win7 | TB | patch re-add D3D9; test VM; nếu hỏng có thể phải ép `--use-angle=d3d9`/blacklist |
| Re-sync gclient (03) revert rust patches | Thấp | 04b idempotent, marker riêng; tài liệu hoá trong README |

## 6. Lộ trình thực hiện

1. Chốt quyết định (xem §7). Tạo branch test trong `chromium/src`: `win7-153.0.8010.37` từ HEAD hiện tại
   (`15359de2eb…` = sau 327 cromite patches).
2. Viết `04b-apply-win7-patches.sh` + dry-run `git apply --check` toàn bộ 336 → **thống kê danh sách fail**
   (ước lượng: vài file overlap cromite + vài file lệch .37).
3. Adapt các diff fail (.27→.37 + overlap) → file override; chạy apply thật; marker; commit history.
4. `07-gn` (WITH_WIN7=1) → `08-build` (siso) → fix compile (dự phòng 2–3 vòng).
5. Packaging: thêm 26100 d3dcompiler, `chrome-win7.zip`.
6. Verify static imports; (tuỳ chọn) VM Win7 smoke test.
7. Tài liệu: README (row 04b, biến `WITH_WIN7`, giới hạn: chỉ 153.0.8010.37 / untested real-hardware nếu vậy).

**Ước lượng:** dry-run + adapt: 0.5–1 ngày; build: 2.5–4h/vòng × 1–3; verify: 0.5 ngày.

## 7. Quyết định cần chốt trước khi làm

1. **PGO:** giữ `chrome_pgo_phase=2` (đã chốt).
2. **CDM/Widevine patch:** skip (đã chốt — cromite không bật Widevine).
3. **Vị trí patch trong repo:** `build/win7-patches/153.0.8010.27/` (đã import + mirror sang `~/cromite-build/cromite/build/`).
4. **SSE3:** chấp nhận hạ về SSE2 theo patch.
5. **Test runtime:** user có máy Win7 → tự smoke test `chrome-win7.zip`.

## 8. Nhật ký thực thi (2026-10-20)

### Thay đổi chiến lược quan trọng

- Các `index` blob trong diff gốc là **trạng thái trung gian tổng hợp** (không tồn tại trong tree
  upstream nào) → `git apply --3way` trực tiếp lên cromite tree **không khả thi**; repo shallow
  (`merge-base` = NONE, `fetch --deepen` fail `expected 'acknowledgments'` trên googlesource).
- Giải pháp thay thế: dựng **worktree vanilla tag 153.0.8010.27** (`~/cromite-build/w7base`) rồi
  chia apply thành 3 phase trong `04b-apply-win7-patches.sh`:

| Phase | Việc | Kết quả |
|---|---|---|
| 1 | Apply từng patch vào B (worktree vanilla .27) trên các path **tracked trong B**, commit từng cái (giữ history, branch `win7-153.0.8010.27`) | 335/335, 0 fail, 270 commit (một số entry không đổi gì) |
| 2 | Sinh delta `git diff 153.0.8010.27..win7-153.0.8010.27` (chỉ path tracked, 1.7 MB) → `git apply --3way` vào A (cromite tree) | 5 conflict, đã resolve tay, commit `f48dcab2dd` |
| 3 | Apply phần **deps** (path không tracked trong B: angle/skia/webrtc/rust-toolchain/mojo/core…) trực tiếp vào A, commit nếu stageable | 335/335, 1 entry auto-skip (đã applied qua phase2), 0 override cần viết |

### Conflict phase 2 đã resolve (giữ hành vi cromite)

- `services/network/public/cpp/stub_resolver_config_reader.cc` — giữ `if ((true)) return false;` của cromite (DoH).
- `ui/gfx/font_loader.h` / `font_cache_skia.cc` / `font_cache_skia_win.cc` — giữ mitigation cromite; font service
  không được compile trong build win64 (0 ref trong `build.ninja`) nên không ảnh hưởng.
- `content/renderer/renderer_blink_platform_impl.cc` — giữ cả block Android (cromite) lẫn include win7.

### Ghi chú

- **Gitlink**: angle/swiftshader/webrtc/icu/dawn/libc++/src/libwebp/src/pdfium/quiche là submodule entry
  (160000) trong parent index + `.gitmodules`; file sửa trong đó **không stage/commit được** vào A
  (changes chỉ nằm ở worktree — build vẫn dùng). Không xoá `.git`/`.gitmodules` để tránh phá repo.
- `04b` có fallback: patch phase3 fail nhưng `git apply -R --check` pass → coi như đã applied qua phase2 → skip.
- **Không cần file override nào** — toàn bộ 335 entry apply được nguyên trạng (3-way lo phần lệch .27→.37).
- Kết thúc apply: `chromium/src` branch `win7-153.0.8010.37`, HEAD `28db9e4e95` (173 commit `[WIN7]`), marker `.win7_patches_applied`.
- B (`w7base`) giữ lại để tham chiếu/rebase khi patchset nguồn cập nhật.
- Verify nhanh sau apply: skia legacy `makeTypeface` re-added, swiftshader `ConvertThreadToFiber` fallback,
  angle d3d9 (`Renderer9.cpp` + `Direct3DCreate9Ex`), rust `windows7.rs` + `c.rs` compat shims — đều OK.

### Build & fixup (cùng ngày)

Build siso `WITH_WIN7=1` pass sau 4 nhóm fixup (bug của patchset gốc chỉ lộ khi **cross-compile từ Linux**,
vì các file cross-platform bị thêm code Win-only không guard — trên Windows native host build = win nên không lộ):

| Fixup | File | Vấn đề |
|---|---|---|
| `overrides/base27/fixups/0001` | `base/files/file_util.cc` | code Win-only (PreReadFile XP fallback) thêm không guard → host Linux vỡ |
| `overrides/deps/fixups/0001` | `v8/src/api/api.cc` | stub ETW URL2 thiếu guard `V8_OS_WIN` |
| `overrides/deps/fixups/0002` | `sandbox/win/src/interception.cc`, `Wow64_64.cc` | include `wow64.h` sai case (patch tạo file `Wow64.h` — chỉ Windows FS mới tha) |
| `overrides/deps/fixups/0003` | `net/base/ip_endpoint.cc`, `third_party/libxml/src/threads.c`, `quiche_ip_address.cc` | Win32 code (GetProcAddress/Interlocked/S_un) thêm không guard |

- `04b` hỗ trợ sẵn cơ chế `overrides/base27/fixups/*.patch` (phase1) và `overrides/deps/fixups/*.patch` (phase3).
- Static import check (`llvm-objdump -p`) trên `chrome.exe/chrome.dll/libEGL/libGLESv2/chrome_elf`: **không còn**
  import trực tiếp API Win8/10-only (WaitOnAddress, ProcessPrng, CreateFile2, GetSystemTimePreciseAsFileTime,
  DPI-for-window…); delay-import chỉ ntdll/kernel32.
- Kết quả: `artifacts/chrome-win7.zip` (205 MB, 466 file; `d3dcompiler_47.dll` = SDK 26100, md5 khớp
  `sdk-26100/…/x64/d3dcompiler_47.dll`). Build default không win7 vẫn nguyên vẹn (`chrome-win.zip`).
- **Chưa test runtime** — cần chạy trên Win7 SP1 x64 thật (user test). Nếu fail load/DLL, xem tiếp
  UCRT/SDK 28000 (rủi ro đã liệt kê §5).

## 9. Tối ưu patchset (2026-10-20)

Yêu cầu: "Tối ưu patches của windows 7" — 3 hướng: (1) lọc code XP/Vista-only, (2) rà soát tính năng bị tắt,
(3) gộp fixups thành override chuẩn. Kết quả chạy lại pipeline từ đầu + rebuild, verify sạch.

### 9.1 Skip list (`overrides/skip/`)

- 50 entry bị skip (file rỗng `<entry>` trong `overrides/skip/`; danh sách + lý do đầy đủ ở
  `overrides/skip/README.md`): nhóm "Remove useless references to unsupported windows versions", XP shims
  (if_indextoname/libxml InitOnce/quiche win32_inet_ntop/QueryThreadCycleTime…), reversal SRWLOCK/InitOnce →
  pthread (libc++/abseil/boringssl/dav1d/ffmpeg/vulkan-loader + libwebp/libvpx/libaom), sandbox XP/wow_helper,
  4 skip "an toàn strip" đã verify removed-side không chứa API Win8+.
- `rust01`/`rust02` skip kèm lý do: chỉ sửa **rust-src component** (`rust-toolchain/lib/rustlib/src/rust/…`);
  build win64 link std prebuilt (`rust-toolchain/lib/rustlib/x86_64-pc-windows-msvc/lib/*.rlib`) nên không vào binary.
- 4 entry skip nhầm đã **bỏ skip** sau feedback của build: `d8ea6f3e` (cung cấp
  `InitializeTsfForInputScopes`/`SetInputScopeForTsfUnawareWindow` cho `cc3c872a`), `1812d0d7` (Remove wow_helper
  revert — cấp `include_dirs` partition_alloc cho `win_hook_util`), `a8bf44a3` (SHFileOperation revert — cấp
  `ProbeOpenCommandHandlers`), `ab240ec5` (cấp định nghĩa `ProbeOpenCommandHandlers` + string grd).
- **`cc84b6cd` skip nhầm — bỏ skip 2026-10-20** sau chẩn đoán crash runtime: delta của entry bỏ
  `/DELAYLOAD:psapi.dll` (và thêm 5 delayloads vào `base_win_linker_flags` trong `base/BUILD.gn`), đúng fix
  cho lỗi delay-load lồng nhau của hook chrome_elf trên Win8.1 — chi tiết ở §10.
- KEEP (đã verify cần cho win7): skia legacy `makeTypeface`, swiftshader GLES legacy (306 file), condvar
  fallback Win7 `f11a6c02`, WAVE audio, DWM, subsystem version 6.x, installer min-OS, sandbox thunk theo OS.

### 9.2 Overrides + fix lệch context

| Override | Nội dung |
|---|---|
| `overrides/deps/531c83c4….patch` | v8 ETW URL2 stub bọc `#if defined(V8_OS_WIN)` (host Linux build) |
| `overrides/base27/ab240ec5….patch` | giữ hunks apply được; 14 hunk lệch context bị bỏ; 2 message `IDS_UNSUPPORTED_OS_PRE_WIN_XP` chèn lại thủ công vào `chromium_strings.grd`/`google_chrome_strings.grd` |

- `1812d0d7` apply với `--exclude=tools/checkbins/checkbins.py` (dev-tooling, context lệch).
- Fix conflict-resolve thiếu `#endif` trong `renderer_blink_platform_impl.cc` (commit riêng).
- Stale state từ pipeline cũ (file ignored/submodule không bị `reset --hard` chạm):
  `rust01/rust02` — file đã patch được khôi phục từ tag `win7-before-opt` rồi **skip** (rust-src không vào binary);
  `dav1d` — `libdav1d` viết lại về pristine (`git -C third_party/dav1d/libdav1d checkout`), chỉ giữ entry kept
  "Add automatic thread count selection" (`cpu.c`); gỡ `cond_locked` mismatch gây undefined symbol khi link.
- Bỏ hẳn cơ chế `overrides/*/fixups/` (4 fixup cũ đã obsolete: file_util do `bb4fe7af` skip; v8 → override;
  wow64 case do `f9b843b9` skip; ip_endpoint/libxml/quiche do entry skip). **Sau đó (audit runtime) cơ chế
  fixups được đưa lại** với 3 patch `overrides/deps/fixups/{10,11,12}` — xem §10 và `fixups/README.md`.

### 9.3 Script 04b

- Thêm skip support cả phase1 & phase3; sửa reverse-check phase2 (bỏ `--3way` khỏi `apply -R --check` — bug báo
  nhầm "already applied"); preflight chặn untracked file lạ trong `chromium/src` trước phase2; phase3 thêm
  fallback `--3way` khi patch fail nhưng file đã tồn tại.

### 9.4 Kết quả

- Pipeline: 335/335 (50 skip), 35 commit `[WIN7]` (trước: 173), HEAD `c472376d5b`, marker cập nhật; build win7
  pass (`Build Succeeded`), chrome-win7.zip đóng gói lại.
- Kích thước: `chrome.exe` 4,085,760 (−24,576 B), `chrome.dll` 307,165,184 (−337,408 B),
  `chrome-win7.zip` 205,026,019 B (−204,046 B so với bản trước).
- Rà soát tính năng bị tắt: `v8_enable_etw_stack_walking=false` giữ (ETW stack-walk là tính năng Win10),
  bỏ `-msse3` giữ (chủ ý tác giả), `treat_warnings_as_errors=false` giữ (chỉ ảnh hưởng build).

## 10. Runtime test Win8.1 — crash `0xC06D007E` do delay-load PSAPI (2026-10-20)

### Triệu chứng

- User chạy `artifacts/chrome-win7.zip` trên **Windows 8.1 x64** (portable `E:\chrome-win\`): chrome mở được
  nhưng mở tab bất kỳ → **"Aw, Snap!"**; Event Viewer 1000 `Exception code 0xC06D007E` (faulting module
  `KERNELBASE.dll`). Các bản thử (gate KsecDD, `chrome-allfix`) đều crash như nhau.

### Chẩn đoán

Build chẩn đoán (đã revert sau khi xong, lưu tại `/tmp/opencode/w7fix/diag-hook.patch`): thêm
`__pfnDliFailureHook2` vào `chrome/chrome_elf/chrome_elf_main.cc` (ghi `elf-delayload.log` vào
module dir/`%TEMP%`/`C:\Windows\Temp`/`%USERPROFILE%`, raise exception mã hoá
`0xE0CC0000 | (dll_index<<8) | name_hash`) + log trong `chrome/app/delay_load_failure_hook_win.cc`.
Android/…-style hash-table decode trong `/tmp/opencode/w7fix/elf-hash-map.txt`.

Log user gửi (process browser, cmdline `"E:\chrome-win\chrome.exe"`, khớp Event 1000 PID 0x1808):

```
6152|PSAPI.DLL|GetMappedFileNameW|reason=3|last_error=0x00000057|code=0xe0cc0407|"E:\chrome-win\chrome.exe"
```

- `reason=3` = `dliFailLoadLib`; `0x57` = `ERROR_INVALID_PARAMETER`; `code 0xe0cc0407`: dll_index 4 =
  `PSAPI.DLL`, hash 7 = `GetMappedFileNameW`.

### Nguyên nhân gốc

1. Hook blocklist DLL bên thứ ba của chrome_elf (`chrome/chrome_elf/third_party_dlls/hook.cc:96`
   `GetSectionName`) gọi `::GetMappedFileName` (delay-import `PSAPI.DLL`) trong khi đang duyệt
   `NtMapViewOfSection`. Hook chỉ chạy ở **browser process** (`DllMain` → `third_party_dlls::Init()`).
2. `psapi.dll` chưa được nạp (delay-load) → lệnh gọi kích hoạt `LoadLibrary("PSAPI.DLL")` **lồng ngay trong
   lúc psapi.dll đang được map**; loader Windows 8.1 trả `STATUS_INVALID_PARAMETER` → delay-load thất bại →
   process browser chết (`0xC06D007E` = mã delay-load failure của MSVC).
3. Upstream không gặp vì entry `cc84b6cd` (bỏ delay-import `psapi.dll`, chuyển sang import tĩnh) luôn được áp;
   trong pipeline ta entry này **bị skip nhầm** (§9.1) do title nghe như cleanup XP.

### Fix

- Bỏ skip `cc84b6cdb2ba06927c498632c86cb0c81e50e9ec` (`overrides/skip/`), `git apply --check` sạch → áp:
  `build/config/win/BUILD.gn` bỏ `/DELAYLOAD:psapi.dll` khỏi `delayloads_except_dbghelp`; `base/BUILD.gn` thêm
  `dbghelp/dwmapi/shell32/uxtheme/propsys` vào `config("base_win_linker_flags")` (config này
  `all_dependent_configs` của target `base`, tương đương hunk `component("base")` gốc của commit upstream).
- Rebuild `chrome` + `chrome_elf` + các exe phụ; verify `llvm-readobj --coff-imports`: `PSAPI.DLL` chuyển từ
  `DelayImport` → `Import` (tĩnh, load từ đầu process) ở `chrome.dll`/`chrome.exe`/`chrome_elf.dll`; exports
  `chrome_elf` giữ nguyên 27.
- Regenerate `overrides/deps/fixups/10-win7-runtime-fixes.patch` (26 file; kèm fix
  `LiveTicksNowIgnoringOverride` + `(void)TimeTicks::IsHighResolution()`), reverse-check OK; sync toàn bộ
  `overrides/` sang `~/cromite-build/cromite`.

### Artifacts cuối (đã bỏ code chẩn đoán)

| File | md5 |
|---|---|
| `chrome.dll` | `1a902484ffbab81ada6aaa967334ad7e` |
| `chrome.exe` | `290e8c2e83d930e5ff8cf75b898dd9ab` |
| `chrome_elf.dll` | `16147c36388c3a39f57cb61540b1b250` |

- `artifacts/chrome-win7.zip` đóng gói lại (205 MB). Bộ test kèm chẩn đoán giao user ở
  `artifacts/test2/` (`chrome-ksec-psapi.dll`, `chrome_elf-diag2.dll`, `chrome-diag2.exe`).
- **Trạng thái: chờ user xác nhận hết "Aw, Snap"**; nếu còn lỗi delay-load khác, log diag sẽ chỉ tiếp.

## 11. Fix fingerprint "không hỗ trợ AES" (2026-10-20)

### Triệu chứng

User báo chrome hiện infobar **"Your device does not support hardware aes, so it is easier to track you
at the network level"** (chuỗi `IDS_UNSUPPORTED_AES_HARDWARE`, `chrome/app/generated_resources.grd`).

### Nguồn & cơ chế

1. Infobar đến từ patch cromite `build/patches/Warning-message-for-unsupported-hardware-aes.patch`
   (uazo 2023-03-24): feature `kNoAESHardwareMessage` **default ENABLED**
   (`cromite_flags/content/public/common/content_features_cc/Warning-message-for-unsupported-hardware-aes.inc`).
2. `chrome/app/chrome_main_delegate.cc:1174` append `switches::kNoAESHardware` khi
   `EVP_has_aes_hardware() == 0`; infobar hiện ở `chrome/browser/ui/startup/bad_flags_prompt.cc:323`.
   Tắt trực tiếp được qua `chrome://flags/#no-hw-aes-warning`.
3. Fingerprint thật sự nằm ở BoringSSL: `EVP_has_aes_hardware()`
   (`third_party/boringssl/src/crypto/fipsmodule/cipher/e_aes.cc.inc:1232` = `hwaes_capable() &&
   crypto_gcm_clmul_enabled()`) trả 0 → client đổi thứ tự cipher TLS 1.3
   (`ssl/handshake_client.cc:130`, `kCiphersNoAESHardware` — ChaCha20 lên đầu) + cấu hình ECH
   (`ssl/encrypted_client_hello.cc:688,748`). NASM asm **có** được build
   (`out/win64/obj/third_party/boringssl/boringssl_asm/aesni-x86_64-win.o`…) → detection là thật;
   CPU/VM Win8.1 của user không có AES-NI.

### Fix (fixup `13-tls-aes-hw-preference.patch`)

- `net/socket/ssl_client_socket_impl.cc`: `bssl::SSL_CTX_set_aes_hw_override_for_testing(ctx, true)`
  trên SSLContext dùng chung (TCP TLS, DoH, WebSockets, proxy) — API BoringSSL duy nhất cho việc này
  (`ssl.h:6865`, trong `BSSL_NAMESPACE_BEGIN`).
- `net/third_party/quiche` (submodule, worktree-only): override tương tự trong
  `TlsConnection::CreateSslCtx()`; `QuicCryptoClientConfig::SetDefaults()` bỏ nhánh
  `EVP_has_aes_hardware()`, luôn `aead = {kAESG, kCC20}` (GQUIC).
- `cromite_flags/.../Warning-message-for-unsupported-hardware-aes.inc`:
  `FEATURE_ENABLED_BY_DEFAULT` → `FEATURE_DISABLED_BY_DEFAULT` (infobar tắt).
- Trade-off: CPU/VM không AES-NI sẽ mã hoá bulk TLS bằng AES phần mềm (chậm hơn ChaCha20) — chấp nhận
  theo yêu cầu user để tránh fingerprint bit tầng mạng.
- Đã `git apply --check` + áp + reverse-check OK; compile lỗi đầu (`SSL_CTX_set_aes_hw_override_for_testing`
  cần prefix `bssl::`) → sửa + rebuild sạch.

### Artifacts (thay thế md5 ở §10)

| File | md5 mới | md5 cũ (§10) |
|---|---|---|
| `chrome.dll` | `274a78db3057690aef426c92e8318ff7` | `1a902484ffbab81ada6aaa967334ad7e` |
| `chrome.exe` | `962cc65654512246a42dfba39d8484d4` | `290e8c2e83d930e5ff8cf75b898dd9ab` |
| `chrome_elf.dll` | `16147c36388c3a39f57cb61540b1b250` | (không đổi) |

- `artifacts/chrome-win7.zip` đóng gói lại (15:04, 205.031.931 B); `artifacts/final/` đã cập nhật.
- **Trạng thái: chờ user test — kỳ vọng hết infobar AES + xác nhận hết "Aw, Snap" (§10).**

## 12. Installer NSIS (2026-10-20)

### Vị trí & pipeline

- Script: `cromite/build/win7-patches/153.0.8010.27/installer/chrome-win7.nsi`
  + `installer/chrome.ico` (trích từ `chrome.exe`, IDR_MAINFRAME, 16–256 px, bằng `wrestool`).
- Build: `scripts/10-installer.sh` (đã thêm vào `build-all.sh` sau `09-package.sh`; cần `apt install nsis`
  — makensis 3.09). Đóng gói `artifacts/chrome-win/` (payload từ 09) → `artifacts/chrome-win7-setup.exe`.

### Thiết kế installer

- NSIS 3.09 Unicode, Modern UI 2, tiếng Anh; **per-machine**: `$PROGRAMFILES64\Cromite`,
  `RequestExecutionLevel admin` (chưa ký số → UAC hiện "Unknown publisher", bình thường).
- `SetRegView 64` toàn cục để OS thấy phần browser registration (nếu ghi vào Wow6432Node sẽ vô hiệu).
- Trang: Welcome → Components (Desktop shortcut, mặc định bật) → Directory → InstFiles → Finish
  (checkbox "Launch Cromite"; chạy qua `explorer.exe` để không kế thừa token admin).
- Đăng ký: Add/Remove Programs (HKLM, `QuietUninstallString` = `/S`), Start Menu (Cromite + Uninstall),
  browser registration tối thiểu (`Clients\StartMenuInternet\Cromite` + `Capabilities` +
  `RegisteredApplications` + ProgID `CromiteURL` cho http/https) → hiện trong "Default Programs",
  **không** ép default; `App Paths\chrome.exe` cho Win+R.
- Uninstall: xóa shortcuts + registry + `RMDir /r $INSTDIR`; **giữ nguyên profile** người dùng.
- Nén `SetCompressor /SOLID lzma` (dict 64 MB, single-thread ~3m23s): payload 493 MB → 135.296.159 B
  (~129 MiB).

### Kiểm chứng trên Linux (không có wine nên không chạy thử được)

- `makensis` biên dịch sạch (chỉ còn warning cosmetic của `MUI_FINISHPAGE_RUN`… đã xử lý).
- `7z t/l` OK: 468 entries, gồm `chrome.dll`/`resources.pak`/`locales/vi.pak`/`uninstall.exe`.
- `wrestool`: có group icon (7 size) + version resource UTF-16 ("Cromite Setup", "153.0.8010.37")
  + manifest (`ManifestSupportedOS all`).

### Artifact

| File | md5 |
|---|---|
| `artifacts/chrome-win7-setup.exe` | `89a3853491d51057eea5496c4c5cc60b` |

- **Trạng thái: chờ user cài thử trên Win8.1** (UAC Yes → `C:\Program Files\Cromite` → shortcut →
  gỡ qua Control Panel; `/S` = silent install). Hạng mục để sau (nếu cần): ký số, per-user install,
  giao diện tiếng Việt, auto-update.

## 13. Fix WebAssembly bị tắt (Proton Pass) — JIT mặc định (2026-10-21)

### Triệu chứng

Proton Pass (web app/extension) báo "Proton Pass requires a modern web browser with cutting edge support
for WebCrypto (PRNG) and Web Storage" + "WebAssembly: Please update to a modern browser with WASM
support" (dù WebCrypto/Web Storage thực tế vẫn OK; chỉ check WASM fail).

### Nguyên nhân gốc (cromite, không liên quan win7)

1. `build/patches/JIT-site-settings.patch` (cromite, từ Bromite) đổi default của content setting
   `JAVASCRIPT_JIT` thành `CONTENT_SETTING_BLOCK` ("disabled by default") —
   `components/content_settings/core/browser/content_settings_registry.cc:578`.
2. `RenderProcessHostImpl::AppendRendererCommandLine` thấy `IsJitDisabled()` → thêm `--jitless` vào
   `--js-flags` của renderer.
3. V8: `DEFINE_IMPLICATION(jitless, wasm_jitless)` (`v8/src/flags/flag-definitions.h:2368`) — jitless kéo
   theo wasm-jitless (interpreter DRUMBRAKE chỉ có ở d8/tvOS, không build trong Chromium) →
   `WebAssembly` không tồn tại trong JS → mọi web app cần WASM đều fail.
   (Từ khoá trong chính patch cromite: `// disable jit but enable webassembly` — họ biết nhưng comment lại.)

### Fix (fixup `14-enable-jit-webassembly.patch`)

- Đổi default về `CONTENT_SETTING_ALLOW` (hành vi Chrome gốc). Setting vẫn hoạt động: site cụ thể vẫn có
  thể bị block JIT (renderer nhận `--jitless`) qua UI content settings.
- Trade-off: bật lại attack surface JIT mà cromite chủ động tắt; **không thể có WebAssembly nếu không có
  JIT** nên đây là lựa chọn bắt buộc nếu muốn Proton Pass/WASM chạy.

### Artifacts (thay thế md5 ở §11)

| File | md5 mới | md5 cũ (§11) |
|---|---|---|
| `chrome.dll` | `ce88f7edaa15591cdba9a6be0645e687` | `274a78db3057690aef426c92e8318ff7` |
| `chrome.exe` | `962cc65654512246a42dfba39d8484d4` | (không đổi) |
| `chrome_elf.dll` | `16147c36388c3a39f57cb61540b1b250` | (không đổi) |
| `chrome-win7-setup.exe` | `daf21851e7e0f197392f4fd70891c2fe` | `89a3853491d51057eea5496c4c5cc60b` |

- `chrome-win7.zip` đóng gói lại (205.030.096 B, 02:03); `artifacts/final/` + installer đã refresh.
- **Trạng thái: chờ user test — mở Proton Pass, kỳ vọng hết báo WebAssembly.**

## 14. Fix lag page/đơ popup (Google account) — throttle 60Hz mặc định của cromite (2026-10-21)

### Triệu chứng (user báo trên Win8.1, GPU Intel Ironlake 2010, driver 8.15.10.2900)

- Vào một số trang nặng thì lag; click mở popup tài khoản Google (overlay Material có animation/blur) thì **đơ cả UI**.
- Nghi vấn kèm theo: popup Proton Pass "UI hiện nhưng click không ăn" (input bị dồn hàng đợi sau frame queue).

### Nguyên nhân gốc (cromite, không liên quan win7)

1. `build/patches/Set-the-screen-frame-rate-to-60-Hz.patch` đặt `kThrottleMainFrameTo60Hz` =
   `CROMITE_FEATURE(..., FEATURE_ENABLED_BY_DEFAULT)` trên **mọi nền tảng** (`cc/base/features.cc:188`).
2. `ChromeContentBrowserClient::AppendExtraCommandLineSwitches`
   (`chrome/browser/chrome_content_browser_client.cc`, nhánh `#if !BUILDFLAG(IS_ANDROID)`) thấy feature bật →
   tự `AppendSwitch(kDisableFrameRateLimit)` vào chính command line của browser.
3. Switch `--disable-frame-rate-limit` được copy sang GPU/renderer (`gpu_process_host.cc`) và tắt bộ giới hạn
   frame nội bộ (`ui/compositor/compositor.cc`, `viz_process_transport_factory.cc`). Trên GPU yếu, mọi hoạt ảnh
   đẩy frame không kiểm soát → bão hòa GPU, frame dồn hàng đợi → lag/đơ UI và input không được xử lý kịp.

### Bằng chứng từ `chrome://gpu` của user

- `Command Line: "...chrome.exe" --profile-directory=Default --no-aes-hardware --flag-switches-begin
  --flag-switches-end --site-per-process --disable-frame-rate-limit`
  - `--disable-frame-rate-limit`: do cromite tự thêm như trên (không phải user).
  - `--site-per-process`: mặc định cromite (patch `Enable-StrictOriginIsolation-and-SitePerProcess`) — bình thường.
  - `--no-aes-hardware`: CPU thiếu AES-NI — khớp bối cảnh fixup 13 (software AES-GCM thay ChaCha20).
- Sau khi user đặt `chrome://flags/#throttle-main-thread-to-60hz` = **Disabled** + Relaunch:
  popup Google **hết đơ**, lag page **hết** → xác nhận nguyên nhân.

### Fix (fixup `15-disable-desktop-60hz-frame-throttle.patch`)

- Đổi default của `kThrottleMainFrameTo60Hz` về `FEATURE_DISABLED_BY_DEFAULT` (khôi phục hành vi desktop của
  upstream Chromium) → không còn append `--disable-frame-rate-limit`.
- Ai muốn throttle 60Hz vẫn bật được qua `chrome://flags/#throttle-main-thread-to-60hz`.

### Artifacts (thay thế md5 ở §13)

| File | md5 mới | md5 cũ (§13) |
|---|---|---|
| `chrome.dll` | `011241e095a78c01632528c51cf89394` | `ce88f7edaa15591cdba9a6be0645e687` |
| `chrome.exe` | `962cc65654512246a42dfba39d8484d4` | (không đổi) |
| `chrome_elf.dll` | `16147c36388c3a39f57cb61540b1b250` | (không đổi) |
| `chrome-win7.zip` | `4a2c8dcda55654591dca904cc2b3600d` (205.031.966 B, 02:56) | `...` (02:03) |
| `chrome-win7-setup.exe` | `4b61c2e74868a7af3aca7af0754085f2` (135.312.659 B, 03:00) | `daf21851e7e0f197392f4fd70891c2fe` |

- `artifacts/final/` đã refresh (chrome.dll/chrome_elf.dll/chrome.exe).
- **Trạng thái: user xác nhận fix đúng qua chrome://flags; chờ test bản build mới.**
- **Còn tồn (item (b)):** popup Proton Pass vẫn chưa click được — tách riêng, cần chẩn đoán tiếp
  (console của popup, hover/keyboard, `--disable-features=CalculateNativeWinOcclusion`, so sánh với extension khác).
  → **Đã fix tại §16** (Viewport Protection OOPIF hit-test).

## 15. Bỏ infobar "you'll need Windows 10 or later" (2026-10-21)

### Triệu chứng

Mỗi lần mở trình duyệt hiện infobar: *"To get future Cromite updates, you'll need Windows 10 or later.
This computer is using Windows 8.1. Learn more"* — upstream Chromium M109+ coi Win7/8/8.1 là obsolete,
nhưng fork này chủ đích hỗ trợ các OS đó nên thông báo là nhiễu.

### Cơ chế

1. `ObsoleteSystem::IsObsoleteNowOrSoon()` (`chrome/browser/obsolete_system/obsolete_system_win.cc`) =
   `GetRealOSVersion() < WIN10`, và `IsEndOfTheLine()` = `CHROME_VERSION_MAJOR >= 109`.
2. `infobar_utils.cc` (~:197) tạo `ObsoleteSystemInfoBarDelegate` khi obsolete, **trừ khi**
   `local_state` có `prefs::kSuppressUnsupportedOSWarning` = true (pref upstream, có cả enterprise policy
   `SuppressUnsupportedOSWarning`).
3. Default của pref đăng ký tại `StartupBrowserCreator::RegisterLocalStatePrefs()`
   (`chrome/browser/ui/startup/startup_browser_creator.cc:942`) = `false` → luôn hiện.

### Fix (fixup `16-suppress-unsupported-os-warning.patch`)

- Đổi default `kSuppressUnsupportedOSWarning` → `true`. Giữ semantics upstream: policy
  `SuppressUnsupportedOSWarning=false` vẫn bật lại được infobar; `IsEndOfTheLine()` vẫn true nên
  upgrade-detector vẫn bỏ qua obsolete OS (không sinh thêm bubble "out of date").
- Không dùng cách patch `IsObsoleteNowOrSoon()=false` vì sẽ vô hiệu hoá luôn cảnh báo ở About/settings
  và bỏ early-return của `UpgradeDetectorImpl::StartOutdatedBuildDetector()`.
- Lưu ý: pref nằm trong `Local State` (`browser.suppress_unsupported_os_warning`); profile đã bị ghi
  `false` từ trước sẽ đè lên default (sửa/xoá khi browser đóng).

### Artifacts (thay thế md5 ở §14)

| File | md5 mới | md5 cũ (§14) |
|---|---|---|
| `chrome.dll` | `1eb08c64c600ecf0a89cc94d2bf23e0e` | `011241e095a78c01632528c51cf89394` |
| `chrome.exe` | `962cc65654512246a42dfba39d8484d4` | (không đổi) |
| `chrome_elf.dll` | `16147c36388c3a39f57cb61540b1b250` | (không đổi) |
| `chrome-win7.zip` | `0425d0e036c5716cfde915c6d1aea5b4` (205.031.928 B, 03:11) | `4a2c8dcda55654591dca904cc2b3600d` |
| `chrome-win7-setup.exe` | `10db282f6d8ba8131d5842ad1fa6be10` (135.317.733 B, 03:15) | `4b61c2e74868a7af3aca7af0754085f2` |

- `artifacts/final/` đã refresh.
- **Trạng thái: chờ user test — kỳ vọng không còn infobar obsolete khi khởi động.**

## 16. Fix click popup Proton Pass (OOPIF) — Viewport Protection device emulation (2026-10-21)

### Triệu chứng

- Popup Proton Pass (cross-origin iframe/OOPIF) hiển thị đúng nhưng **click không ăn** — click rơi xuống
  trang cha. Đây là item (b) tồn đọng từ §14.
- Chỉ xảy ra khi Viewport Protection bật (mặc định của cromite) và với iframe khác origin
  (Proton Pass, khả năng cả Turnstile/Cloudflare).

### Nguyên nhân gốc (cromite, không liên quan win7)

1. Viewport Protection (blink `kViewportProtection`) random `scale` mỗi origin/navigation
   (`page.cc: CalculateEmulatedScreenSetting`, `scale = 1/(1+half_random)`; đo được 1.0022–1.0105) và chạy
   tab qua `ScreenMetricsEmulator`: widget renderer bị **phóng to ×1/scale** (Blink space), còn compositor
   vẽ thu nhỏ lại ×scale (transform node trên visual viewport).
2. `WebFrameWidgetImpl::GetFrameSinkIdAtPoint()` hit-test điểm DIP **thô** trong không gian Blink đã phóng
   to → toạ độ local trả về cho iframe lệch `a×(1−1/scale)` (~2.7 px @ x≈1350 với scale 1.0022; ~11 px
   với scale 1.009).
3. Browser đối chiếu câu trả lời với phép biến đổi viz của chính nó (`RenderWidgetTargeter`, epsilon 2 px)
   → GEOM fail → target rơi về ROOT (trang cha) → click bị nuốt.
4. Chẩn đoán bằng build có log `[HITTEST]` (RFM/VPROP/XFORM/GEOM/REPLY, các bản v5–v7); số liệu khớp
   đúng công thức lệch ở (2).

### Fix (fixup `17-viewport-protection-hittest-fix.patch`)

- Trong `GetFrameSinkIdAtPoint()`: khi `DeviceEmulator()` hoạt động, nhân điểm hit-test với
  `1/emulation_scale` trước `CoreHitTestResultAt()` — khớp với `ScreenMetricsEmulator::Apply()`.
- Không đụng transform hiển thị hay các path khác (event forward xuống child vốn đã đúng qua viz).
- **Trạng thái: user xác nhận fix thành công** — GEOM pass (`resolved=CHILD final=CHILD`), popup Proton
  Pass click được; Viewport Protection vẫn hoạt động bình thường. Bản build này đã gỡ toàn bộ log chẩn
  đoán `[HITTEST]`, chỉ còn fix.

### Artifacts (thay thế md5 ở §15)

| File | md5 mới | md5 cũ (§15) |
|---|---|---|
| `chrome.dll` | `62647e8bcb4d49e8f63a6e515454b463` | `1eb08c64c600ecf0a89cc94d2bf23e0e` |
| `chrome.exe` | `962cc65654512246a42dfba39d8484d4` | (không đổi) |
| `chrome_elf.dll` | `16147c36388c3a39f57cb61540b1b250` | (không đổi) |
| `chrome-win7.zip` | `9e6e0a80524fafd7cbcc31f8f4621b61` (205.035.569 B, 11:52) | `0425d0e036c5716cfde915c6d1aea5b4` |
| `chrome-win7-setup.exe` | `911913b99a0204da9f2118787d2a4340` (135.305.769 B, 11:56) | `10db282f6d8ba8131d5842ad1fa6be10` |

- `artifacts/final/` đã refresh (chrome.dll/chrome_elf.dll/chrome.exe).
- Ghi chú: đây là bug của Viewport Protection (không riêng win7) — có thể báo upstream uazo/cromite kèm patch này.

## 17. Fix dải đen cửa sổ DevTools (popup layout + native caption) (2026-10-21)

### Triệu chứng

- Cửa sổ DevTools (undocked) trên Win8.1: một **dải đen** giữa thanh caption hệ thống và nội dung
  frontend (nội dung bị đẩy xuống).
- Chỉ cửa sổ DevTools bị: tắt GPU (`--disable-gpu`) vẫn đen; zoom/đổi panel/resize không đổi;
  các cửa sổ browser thường bình thường.

### Nguyên nhân gốc (win7 delta + layout popup của M153)

1. Cửa sổ DevTools là browser type `TYPE_DEVTOOLS` → được layout bằng
   `BrowserViewPopupLayoutImpl::CalculateTopContainerLayout()` ("Layout starts beneath the caption
   buttons… title is laid out by the OS in popup mode"): layout **luôn chừa một dải trên** bằng chiều
   cao exclusion caption-buttons (~`GetFrameHeight()` ≈ chiều cao titlebar).
2. Exclusion do `BrowserFrameViewWin::GetBrowserLayoutParams()` cung cấp từ bounds của
   `caption_button_container_` — được tính vô điều kiện, kể cả khi cửa sổ dùng native caption.
3. Trên Win10+ dải đó được `PaintTitlebar()` vẽ (Chrome tự vẽ titlebar). Bản win7 trên Win8.1:
   `ShouldBrowserCustomDrawTitlebar()` = false (delta guard `< WIN10`) và delta bỏ
   `PaintTitlebar()` → dải bị chừa nhưng **không ai vẽ**. Nội dung cửa sổ lại trong suốt
   (`ShouldWindowContentsBeTransparent()` = true khi Aero) → DWM composite vùng trống thành **đen**.

### Fix (fixup `18-devtools-popup-caption-strip-fix.patch`)

- `GetBrowserLayoutParams()`: với cửa sổ popup-type dùng native frame
  (`!GetIsNormalType() && !IsOpaqueHostedAppFrame() && !ShouldBrowserCustomDrawTitlebar()`), trả về
  params **không kèm exclusion** → popup layout không chừa dải → nội dung DevTools lên sát caption.
- Giữ nguyên exclusion cho web app frame (tự vẽ nút trong client area) và cửa sổ tabbed thường.
- **Trạng thái: user xác nhận fix thành công** trên Win8.1 — dải đen mất, dock/undock/zoom/đổi panel
  bình thường.

### Artifacts (thay thế md5 ở §16)

| File | md5 mới | md5 cũ (§16) |
|---|---|---|
| `chrome.dll` | `e8edf6149604ed0a53b8fb83d41cdf2c` | `62647e8bcb4d49e8f63a6e515454b463` |
| `chrome.exe` | `962cc65654512246a42dfba39d8484d4` | (không đổi) |
| `chrome_elf.dll` | `16147c36388c3a39f57cb61540b1b250` | (không đổi) |
| `chrome-win7.zip` | `a688c301f4a05b054efbbb3991cd72f8` (205.033.780 B, 12:43) | `9e6e0a80524fafd7cbcc31f8f4621b61` |
| `chrome-win7-setup.exe` | `b0f3d9b4a5cd0bf7f1f2bceed2932b9d` (135.303.733 B, 12:47) | `911913b99a0204da9f2118787d2a4340` |

- `artifacts/final/` đã refresh (chrome.dll/chrome_elf.dll/chrome.exe).
- Ghi chú: đây là bug tương tác giữa layout popup của M153 với native caption (không riêng win7 — sẽ
  gặp khi chạy native frame trên Win10 bằng theme hệ thống); có thể báo upstream kèm patch này.

## 18. Fix video x.com "không thể phát phương tiện" — mở lại ffmpeg software decoder cho H.264/AAC (2026-10-22)

### Triệu chứng (user báo trên Win8.1, GPU Intel Ironlake 2010, driver 8.15.10.2900)

- Video trên **x.com** báo *"không thể phát phương tiện"* (mọi video, kể cả video có tiếng);
  **YouTube phát bình thường**.
- `chrome://gpu`: `Video Decode: Hardware accelerated` (D3D11) — driver cũ fail đường decode cứng
  nhưng không còn đường dự phòng nào khác.

### Nguyên nhân gốc (cromite, không liên quan win7)

1. Patch cromite `build/patches/Enable-platform-aac-audio-and-h264-video.patch` + hai GN args
   `enable_platform_aac_audio = true`, `enable_platform_h264_video = true` (bản win7 đang build —
   mục đích upstream là dùng thư viện hệ thống thay ffmpeg vì licence). Hai flag được dịch thành
   buildflag `ENABLE_PLATFORM_AAC_AUDIO`/`ENABLE_PLATFORM_H264_VIDEO` và **tắt hẳn decoder mềm ffmpeg**
   cho đúng codec đó:
   - `media/filters/ffmpeg_video_decoder.cc`: `IsCodecSupported()` trả `false` cho `kH264`.
   - `media/filters/ffmpeg_audio_decoder.cc`: `kAAC` → `kUnsupportedProfile`.
   - kèm `media/gpu/windows/supported_profile_helpers.cc` mở max H.264 resolution lên 4096x2304 và
     MediaFoundation AAC dùng ADTS (`wPayloadType = 1`).
2. Hệ quả: H.264 chỉ còn **duy nhất** decoder cứng D3D11, AAC chỉ còn MediaFoundation. Trên Intel
   Ironlake + driver 8.15.10.2900 đường decode cứng fail → **không còn fallback** → pipeline báo lỗi
   decode, player của x.com hiện "không thể phát phương tiện".
3. YouTube không dính vì dùng **VP9/Opus** (decoder mềm libvpx/ffmpeg — không bị hai flag này đụng).

### Fix (build args — không phải patch nguồn)

- `build/cromite.gn_args`: trong nhánh `if (target_os == "win")` đặt lại
  `enable_platform_aac_audio = false`, `enable_platform_h264_video = false`. Với `proprietary_codecs=true`
  + `ffmpeg_branding="Chrome"`, hai decoder mềm ffmpeg được build trở lại.
- Hardware decode D3D11 vẫn được ưu tiên khi chạy được; khi driver cũ fail → tự rơi về ffmpeg
  (chỉ tốn thêm CPU lúc software decode; chấp nhận được với máy cũ). YouTube/VP9 không đổi.
- Android giữ nguyên `true` (override nằm trong nhánh win nên không ảnh hưởng build android).
- Xác nhận qua `out/win64/gen/media/media_buildflags.h`: `ENABLE_PLATFORM_AAC_AUDIO=0`,
  `ENABLE_PLATFORM_H264_VIDEO=0`.
- Đánh đổi: quay lại dùng decoder mềm ffmpeg cho H.264/AAC (khác với hướng licence của upstream
  cromite); muốn về hành vi cũ chỉ cần đổi lại hai args thành `true`.

### Artifacts (thay thế md5 ở §17)

| File | md5 mới | md5 cũ (§17) |
|---|---|---|
| `chrome.dll` | `542c4bd71519b3b8ee6f60187095c8ca` | `e8edf6149604ed0a53b8fb83d41cdf2c` |
| `chrome.exe` | `962cc65654512246a42dfba39d8484d4` | (không đổi) |
| `chrome_elf.dll` | `16147c36388c3a39f57cb61540b1b250` | (không đổi) |
| `chrome-win7.zip` | `086f0fcb24df6eff452182941706ad34` (205.035.822 B, 15:00) | `a688c301f4a05b054efbbb3991cd72f8` |
| `chrome-win7-setup.exe` | `f3efdf1a2cdfaf26bc87f18303fc53e3` (135.362.514 B, 15:05) | `b0f3d9b4a5cd0bf7f1f2bceed2932b9d` |

- `artifacts/final/` đã refresh (chrome.dll/chrome_elf.dll/chrome.exe).

## 19. Fix chữ mờ trong modal/popup — khôi phục ClearType (font rendering hệ thống) (2026-10-22)

### Triệu chứng (user báo trên Win8.1, kèm screenshot Facebook post dialog)

- Chữ trong modal/popup (bài viết Facebook) mờ/mềm; user tự đánh giá "sai thiết kế" so với Chrome thường.
- Nền sau modal bị blur là **thiết kế của Facebook** (`backdrop-filter` trong keyframes dialog của fb —
  xác nhận trong `fb1.css`), không phải bug.

### Chẩn đoán

- Pixel forensics screenshot: **toàn bộ pixel chữ trong modal neutral RGB** (R≈G≈B, không có fringe
  ClearType) → text đang được render bằng **grayscale antialiasing**.
- Chuỗi nhân quả trong code: `gfx::FontRenderParams` (browser) →
  `renderer_preferences_.subpixel_rendering` → `WebViewImpl::UpdateFontRenderingFromRendererPrefs()`
  → `WebFontRendering::SetLCDTextEnabled()` → `FontCache::lcd_text_enabled_` →
  `FontPlatformData::QuerySystemForRenderStyle()` → `CreateSkFont()` chỉ bật
  `kSubpixelAntiAlias` khi subpixel rendering ≠ NONE.
- `ui/gfx/font_render_params_win.cc` (bản build) bị cromite ép `SUBPIXEL_RENDERING_NONE` toàn cục:
  `Do-not-use-Windows-ClearType-Text-Tuner-setting.patch` thêm 3 override `if ((true))`
  (`GetSubpixelRenderingGeometry`, `GetTextSettingsRegistryKey`, nhánh `GetParams`).
  Trên máy bật ClearType (mặc định Win7/8/8.1), Chrome gốc render subpixel (fringe màu) nét hơn hẳn
  grayscale AA → user thấy "chữ mờ" (rõ nhất trong modal vì nền đã bị blur).

### Fix (fixup `19-restore-cleartype-font-rendering.patch`, `ui/gfx` 2 file)

- Bỏ 3 override `if ((true))`, trả về hành vi stock Chrome: đọc `SPI_GETFONTSMOOTHING` +
  `SPI_GETFONTSMOOTHINGTYPE` (ClearType), geometry từ registry `PixelStructure` /
  `SPI_GETFONTSMOOTHINGORIENTATION`; mở lại `GetTextSettingsRegistryKey` (kèm gamma/contrast tuner).
- Giữ nguyên tinh chỉnh win7 `win::IsDirectWriteEnabled()` trong cùng block (Win7 GDI không subpixel
  positioning).

### Xác minh

- Diff bitcode LLVM của `font_render_params_win.obj` (clang 24 `-x ir`) chứa đúng chuỗi stock:
  `SystemParametersInfoW(74)` (SPI_GETFONTSMOOTHING) → `IsDirectWriteEnabled()` →
  `SystemParametersInfoW(8202)` (SPI_GETFONTSMOOTHINGTYPE) `== FE_FONTSMOOTHINGCLEARTYPE` →
  `GetTextSettingsRegistryKey` + `ReadValueDW("PixelStructure")` →
  `SystemParametersInfoW(8210)` (SPI_GETFONTSMOOTHINGORIENTATION).
- Build incremental OK (2 obj + relink), zip + installer đóng gói lại.

### Artifacts (thay thế md5 ở §18)

| File | md5 mới | md5 cũ (§18) |
|---|---|---|
| `chrome.dll` | `1d73fc5663231d9712a66c888140da97` | `542c4bd71519b3b8ee6f60187095c8ca` |
| `chrome.exe` | `962cc65654512246a42dfba39d8484d4` | (không đổi) |
| `chrome_elf.dll` | `16147c36388c3a39f57cb61540b1b250` | (không đổi) |
| `chrome-win7.zip` | `0d27759336166d46e65c61c1e7ce84f5` (205.033.025 B, 06:07) | `086f0fcb24df6eff452182941706ad34` |
| `chrome-win7-setup.exe` | `9abf8d76470205588170c1ebaf34da3e` (135.321.216 B, 06:14) | `f3efdf1a2cdfaf26bc87f18303fc53e3` |

- `artifacts/final/` đã refresh (chrome.dll/chrome_elf.dll/chrome.exe).
- Đánh đổi: mở lại các fingerprint bit của ClearType tuner (hướng, gamma/contrast) mà cromite cố che;
  muốn quay lại hành vi cromite thì bỏ fixup này (không có flag).
- Trạng thái: build xong, chờ user xác nhận trên Win8.1 (so sánh chữ trong modal trước/sau).

## 20. Fix nốt phần chữ mờ còn lại — ép LCD text toàn bộ layer renderer (2026-10-22)

### Phản hồi user sau fixup 19

- "Không thay đổi text, vẫn còn blur" + 2 screenshot mới (modal FB + bubble Proton).
- Nhưng forensics cho thấy **build mới ĐÃ có hiệu lực**: URL bar (omnibox) trong ảnh mới có fringe
  ClearType rõ (R−B trải −119..+110, ~38% pixel mỗi phía); ảnh cũ cùng vị trí chỉ −7..0 (neutral tuyệt
  đối) → Windows ClearType đang bật + fixup 19 đang chạy (không cần certutil/reg nữa).
- Chữ **trong modal FB** (title, caption trên video, comment, composer) và **bubble Proton** vẫn
  chroma ≈ 0 → vẫn grayscale.

### Nguyên nhân (đã tra source)

- Renderer tắt LCD text **theo từng layer**: `cc::PictureLayerImpl::ComputeLCDTextDisallowedReason()`
  trả lý do khác `kNone` khi layer có `will-change: transform` (`kWillChangeTransform`), đang animate
  transform (`kTransformAnimation`), `filter`/`backdrop-filter` (`kPixelOrColorEffect`), offset lẻ
  (`kNonIntegral*`), hoặc nền/contents không đục (`kContentsNotOpaque`/`kBackgroundColorNotOpaque`)
  → tile raster bằng grayscale AA, **là hành vi stock của mọi Chromium** (Chrome/Edge gốc y hệt).
- Dialog FB trúng nhiều điều kiện: animation mở bằng transform, canh giữa `translate(-50%,-50%)`
  (offset .5px), `will-change`, nền overlay có blur → cả cây dialog grayscale.
- Toolbar/omnibox miễn nhiễm vì compositor UI hard-code `settings.layers_always_allowed_lcd_text = true`
  (`ui/compositor/compositor.cc`, kèm comment "to match the previous behaviour with ContentLayers") —
  đó là lý do cùng một ảnh, omnibox có fringe còn modal thì không.

### Bằng chứng trên máy user (text-test.html, `artifacts/final/`)

| Panel | Điều kiện | Kết quả đo |
|---|---|---|
| A + tab title | text thường | fringe ClearType: R−B ±179, 83% pixel có màu |
| B | card trên nền `backdrop-filter` | chroma = **0.00** tuyệt đối (grayscale) |
| C | card `will-change:transform, opacity` | chroma = **0.00** |
| D | card `opacity:.999` | chroma = **0.00** |
| E | card `scale(1.001)` | chroma = **0.00** |

→ Cơ chế được chứng minh trực tiếp trên máy user; B/C/D/E đúng chữ ký của modal FB.

### Fix (fixup `20-force-lcd-text-in-renderer.patch`, `third_party/blink` 1 file)

- `blink::GenerateLayerTreeSettings()`: thêm `settings.layers_always_allowed_lcd_text = true;`
  → mọi layer web content raster text bằng subpixel AA như UI compositor (không còn phụ thuộc
  transform/opacity/backdrop).
- Đánh đổi: layer có thể bị composite lệch nửa pixel / resample (lúc animation scale) → có thể thấy
  thoáng viền màu trên chữ trong lúc modal mở/đóng; nếu thấy xấu → bỏ fixup (hoặc khôi phục
  `chrome-baseline-fixup19.dll`), không có flag.

### Artifacts

| File | md5 mới (fixup 20) | baseline fixup 19 |
|---|---|---|
| `chrome.dll` | `3cea7cbb3db648b12a90fb8e7fdec01a` | `1d73fc5663231d9712a66c888140da97` (`artifacts/chrome-baseline-fixup19.dll`) |
| `chrome-win7.zip` | `429deebc05ff45cf5ba3ecaec07db8c7` (205.035.063 B, 09:43) | `0d27759336166d46e65c61c1e7ce84f5` (`artifacts/chrome-win7-fixup19-baseline.zip`) |
| `chrome-win7-setup.exe` | `fd856feb475aefbbd23e2a860bbe0d21` (135.370.613 B, 09:47) | `9abf8d76470205588170c1ebaf34da3e` |

- `artifacts/final/` đã refresh (kèm `text-test.html`).
- Trạng thái: build xong, chờ user A/B trên Win8.1 (modal FB + bong bóng Proton nét fringe? viền màu
  lúc animation có khó chịu không?).

### Kết quả test của user

- Bubble Proton + text trang: có fringe ClearType rõ (số đo: sub-item xám R−B −89..+50; input text
  −141..+97; so với trước fixup 20: bubble 0% phía dương) → fixup 20 hoạt động đúng thiết kế.
- Tuy nhiên user báo "lần này YouTube lại bị" và yêu cầu **revert fixup 20 + điều tra toàn bộ
  patches**.

### REVERT (2026-10-22)

- Tree: `git revert e912407f39` (commit `b7d6a01baf`). Patch chuyển sang
  `overrides/deps/fixups/reverted/20-force-lcd-text-in-renderer.patch` (glob `fixups/*.patch`
  không với tới thư mục con → build sau không còn áp dụng).
- Artifacts: `chrome-win7.zip`/`chrome-win7-setup.exe` quay lại bản fixup 19 (md5 `0d277593...`);
  bản fixup 20 đổi tên thành `chrome-win7-lcdtext-experiment.zip`/`-setup.exe`.
- Không tìm thấy cơ chế nào nối flag raster hóa chữ với phát video; revert để có trạng thái sạch
  điều tra YouTube. Muốn bật lại: chuyển patch về `fixups/`.

### Điều tra YouTube (đang làm)

- Audit nhóm patch đụng media/gpu — ứng viên chính:
  - win7 `689e7aa6b9` (re-add) bật `kD3D11VideoDecoder` + VP9Profile2 + AV1 **ENABLED_BY_DEFAULT**
    → D3D11 decode được thử trên Ironlake (driver 2010); §18 cho thấy driver fail đường cứng.
  - win7 `26ba560951` (win7dep media/), `36b5c3f874` (gpu_mojo_media_client_win), `dedaa2707f`
    (VEA Win7 — chỉ encode).
  - cromite: `Enable-platform-aac-audio-and-h264-video` (đã xử lý ở §18),
    `Media-fingerprinting-mitigations` (chỉ WebCodecs VideoDecoder → kPreferSoftware; không ảnh
    hưởng MSE/YouTube), `AudioBuffer-AnalyserNode-fp-mitigations`, `Disable-DRM-media-origin-IDs`.
- Cấu hình codec hiện tại: `proprietary_codecs=true`, `ffmpeg_branding="Chrome"`,
  `enable_av1_decoder/dav1d=true`, platform AAC/H264 = false (ffmpeg SW còn),
  `media_use_openh264=false`.
- Cần user xác nhận triệu chứng YouTube cụ thể (video đen/lỗi/không tiếng/giật; chỉ live hay mọi
  video; kèm `chrome://media-internals` + `chrome://gpu`) trước khi kết luận patch nào.

## 21. Fix chọn lọc chữ mờ trên YouTube (will-change containers) — LCD text cho layer pixel-aligned (2026-10-22)

### Triệu chứng (user: "YouTube lại bị, phần chữ bị blur")

- Sau fixup 20 (revert) + làm rõ: vấn đề là **chữ**, không phải video.
- Đo trên screenshot YouTube của user: chữ sidebar ("Trang chủ", "Kênh đăng ký"),
  tiêu đề video = **grayscale AA** (chroma ≈ 0, mờ nhẹ); chữ metadata / ô "Tìm kiếm" = đã
  ClearType (R−B ±38..±51, 2 phía). → phần còn mờ là text trong layer `will-change: transform`
  (YouTube dùng rất nhiều cho sidebar/lưới thumbnail).

### Nguyên nhân

- `cc::PictureLayerImpl::ComputeLCDTextDisallowedReason()` trả `kWillChangeTransform` chỉ vì node
  transform có cờ will-change — **dù layer đang đứng yên và được raster đúng pixel**
  (`raster_translation_aligns_pixels = true`, xem `CalculateRasterTranslation()` /
  `PixelAlignmentOffset()`). Đây là hành vi stock nhưng với user (máy 1.0x DPI, mắt quen ClearType)
  rất rõ.
- Ép toàn bộ như fixup 20 quá thô: layer bị resample (animation/offset lẻ/filter) cũng bị raster
  subpixel → compositor resample → **nhòe + nhiễu màu** (đúng phản hồi "YouTube bị" của user) → đã revert.

### Fix (fixup `21-allow-lcd-text-on-pixel-aligned-layers.patch`, `cc` 1 file)

- Đảo thứ tự kiểm tra trong `ComputeLCDTextDisallowedReason`:
  - `kTransformAnimation` vẫn chặn vô điều kiện (đang chạy animation → grayscale, an toàn).
  - `kWillChangeTransform` / `kPixelOrColorEffect` (filter/backdrop) / `kNonIntegral*` **chỉ xét khi
    `raster_translation_aligns_pixels == false`**.
  - `kContentsNotOpaque`/`kBackgroundColorNotOpaque` giữ nguyên (nền không đục vẫn grayscale).
- Hệ quả: layer **vẽ 1:1 đúng pixel** (tĩnh, aligned) được raster subpixel → nét; layer có khả năng
  bị resample giữ grayscale → không tái hiện lỗi nhòe của fixup 20.
- Kỳ vọng: sidebar/tiêu đề YouTube nét; dialog FB lúc đứng yên nét; bubble extension nét; lúc
  animation/scale vẫn grayscale như stock. Đánh đổi: animation tịnh tiến (translate) có thể giữ LCD
  (Chromium snap vị trí layer về pixel nguyên).

### Artifacts (thay md5 §20)

| File | md5 mới (fixup 21) | baseline fixup 19 |
|---|---|---|
| `chrome.dll` | `d0eb122814acfc547a89465bfb257be3` | `1d73fc5663231d9712a66c888140da97` |
| `chrome-win7.zip` | `267796338e68c398928d5786f40f4f2a` (205.031.138 B, 10:10) | `0d27759336166d46e65c61c1e7ce84f5` |
| `chrome-win7-setup.exe` | `5ff128de890836a9fdc43eec9c8484a5` (135.287.666 B, 10:13) | `9abf8d76470205588170c1ebaf34da3e` |

- Bản fixup 20 (ép toàn bộ) giữ ở `chrome-win7-lcdtext-experiment*.zip/exe` để tham chiếu.
- Trạng thái: build xong, chờ user test YouTube + modal FB + bubble + text-test.html.

## 22. Chữ nét trên panel trong suốt (bubble Proton Pass) — LCD text cho layer aligned không đục (2026-10-22)

### Triệu chứng (user: ảnh bubble "Save passkey")

- Đo trên screenshot `r133615.png`: toàn bộ chữ trong bubble ("Save passkey", "webauthn.io",
  "123454", "Create new login") = **grayscale AA 100%** (0% pixel lệch khỏi đường blend
  core↔nền; nền blob xanh/tím mờ = thiết kế của trang, không phải lỗi code).
- Bubble là OOPIF của extension (đường web content) → chịu `ComputeLCDTextDisallowedReason`;
  fixup 21 vẫn để grayscale vì cổng opaque (`kBackgroundColorNotOpaque`/`kContentsNotOpaque`) —
  panel bo góc/nội dung không đục (đã đối chiếu: đây là cổng duy nhất còn lại khớp với ảnh đo).

### Fix (fixup `22-allow-lcd-text-on-aligned-translucent-layers.patch`, `cc` 1 file)

- Với layer **pixel-aligned**: bỏ 2 cổng opaque → trả `kNone` (LCD) kể cả khi nền/nội dung
  không đục. Layer 1:1 thì glyph subpixel không bị smear; viền glyph blend theo subpixel với
  pixel trong suốt — đúng kiểu ClearType.
- Layer không aligned (offset lẻ, animation, will-change chưa aligned) vẫn grayscale như trước
  (nhánh `!raster_translation_aligns_pixels` giữ nguyên) → không tái hiện lỗi nhòe fixup 20.
- Rủi ro: chữ trên panel trong suốt nền loang lổ sẽ có viền màu ClearType (bình thường); nếu
  panel nào trông tệ hơn thì bỏ fixup này.

### Artifacts (thay md5 §21)

| File | md5 (fixup 22) | baseline fixup 19 |
|---|---|---|
| `chrome.dll` | `f4f20ab8cb651b8da1cdbf911b290af4` | `1d73fc5663231d9712a66c888140da97` |
| `chrome-win7.zip` | `a8f5fa2961d7b02cbbf5e8181bb0eb09` (205.033.285 B, 10:40) | `0d27759336166d46e65c61c1e7ce84f5` |
| `chrome-win7-setup.exe` | `bea310a14a76d6d6164262986522120c` (135.326.326 B, 10:45) | `9abf8d76470205588170c1ebaf34da3e` (135.321.216 B) |

- Nếu bubble vẫn grayscale sau fixup 22 → layer bubble **không aligned** (vị trí lẻ pixel /
  đang animation) → cần fixup 23 probe (log LCD reason) mới kết luận được.
- Trạng thái: build xong, chờ user test bubble + YouTube + text-test.

### Kết quả & revert (cùng ngày)

- User báo: **"Tệ hơn so với trước"** kèm ảnh bubble mới (`r133850.png`).
- Đo ảnh: fixup 22 **đã bật ClearType thật** cho bubble — viền màu đúng hướng (C ở mép trái glyph,
  R ở mép phải), viền rộng 1px (không resample), R−B tới ±117. Nhưng so ảnh cũ/mới phóng 4x:
  chữ **trắng trên nút tím** và chữ **tím trên card trắng** nhỏ → viền đỏ/lam rất rõ; gamma
  subpixel làm glyph **dày/đậm hơn hẳn** so với grayscale mượt trước đó (nét run tăng 2→4px).
- Kết luận: đây chính là lý do stock Chromium chặn LCD trên panel không đục/bo góc
  (`kBackgroundColorNotOpaque`/`kContentsNotOpaque`) — không phải bug. Ép LCD ở UI nhỏ nhiều màu
  cho kết quả tệ hơn grayscale.
- **Đã revert fixup 22** (tree `d4ffe11ec7`; patch chuyển vào `fixups/reverted/`), build lại:
  `chrome.dll` md5 `d0eb122814acfc547a89465bfb257be3` — **trùng khớp tuyệt đối với build fixup 21**.

| File | md5 (fixup 21 khôi phục, 2026-10-22 11:37) |
|---|---|
| `chrome.dll` | `d0eb122814acfc547a89465bfb257be3` |
| `chrome-win7.zip` | `6c1849f828b4eb912c4cc486ab30b358` (205.031.138 B, 11:33) |
| `chrome-win7-setup.exe` | `672dd59ca470fb1bd921e064ed7386d2` (135.321.008 B, 11:37) |

- Bản fixup 22 giữ tham chiếu ở `chrome-win7-fixup22-lcdbubble-experiment*.zip/exe`.
- Trạng thái bubble Proton: giữ grayscale (mượt) theo stock; để nét hơn thì chỉ còn cách ép LCD —
  đã chứng minh là tệ hơn, nên đóng hướng này.

### Chuỗi code đầy đủ của cơ chế LCD/grayscale (truy hết, 2026-10-22)

1. `cc/layers/picture_layer_impl.cc:706` `ComputeLCDTextDisallowedReason` — cổng chặn theo layer.
   Thí nghiệm fixup 22 chứng minh bubble chỉ bị chặn bởi `contents_opaque_for_text()==false`
   → `kContentsNotOpaque` (layer aligned, không animation, không filter-gate).
2. `cc/tiles/tile_manager.cc` — `PlaybackSettings.use_lcd_text = tile->can_use_lcd_text()`.
3. `cc/paint/paint_op_buffer_serializer.cc:37-40` — `can_use_lcd_text` đi vào surface props khi
   serialize (`skia::LegacyDisplayGlobals::ComputeSurfaceProps(...)`).
4. `gpu/command_buffer/service/raster_decoder.cc:2868-2872` — **công tắc thật**:
   `SkSurfaceProps(flags, kUnknown_SkPixelGeometry)` để tắt LCD (comment stock: "Use unknown pixel
   geometry to disable LCD text"); nếu `can_use_lcd_text` thì dùng pixel geometry của màn hình
   (RGB/BGR từ Windows) → Skia raster glyph subpixel.
5. Edging của font: `third_party/blink/renderer/platform/fonts/win/font_platform_data_win.cc:52-58`
   và `.../web_font_render_style.cc:94-102` — `SkFont::Edging::kSubpixelAntiAlias` theo cài đặt
   ClearType của Windows (chính chỗ fixup 19 khôi phục).
6. Chữ ký định lượng của "tệ hơn" (đo ảnh cũ/mới): advance từng ký tự y hệt (9/4/7 px), chiều cao
   y hệt → **không đổi font/weight**; chỉ mực (ink) tăng **+56–79%** (gamma/độ dày đường subpixel)
   + viền màu đỏ/lam đúng hướng. Trên nền bão hoà (chữ trắng/nút tím) và chữ nhỏ, hai hiệu ứng này
   rõ nhất → grayscale mượt nhìn tốt hơn. Đây là bản chất subpixel, không có knob để "LCD mà không
   đậm/không viền" ⇒ stock gates là đúng; đóng hướng này.
