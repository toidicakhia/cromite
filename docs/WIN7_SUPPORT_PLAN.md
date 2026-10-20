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
