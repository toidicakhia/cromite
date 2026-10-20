# Windows 7 patchset — entry skip list

Format: entry | upstream commit | reason. Generated 2026-10-20.

- 4272e0fd06fa417c03289344a49c75054ea4b5f1 — Remove useless references to unsupported windows versions  — re-add dead XP/Vista version refs (upstream "useless references (3)")
- af4d0ad7d9233c1023b34c21540256aa424e7773 — Remove useless references to unsupported windows versions  — same series (1)
- bea7178baa44e7506cdf7afaedb9fffa04007842 — Remove useless references to unsupported windows versions  — same series (2)
- ac2e6192636293e1c08f757f2780f950450e2861 — Remove Windows XP support code in LocaleWin.cpp.    2016/1 — LocaleWin XP-only code
- aa3cff336c91fbe2cd8cc6254736564d95c5b230 — Cleanup: LFH only needs to be enabled on XP/2003    2016/3 — LFH enabled on XP/2003 only
- 18ad5f3a40ceab583961ca5dc064e01900514c57 — zlib: Remove Windows XP workaround for CPU feature detecti — zlib XP CPU detection workaround
- cc84b6cdb2ba06927c498632c86cb0c81e50e9ec — Remove user32 delay imports for XP, more GN imports match  — user32 delay imports for XP
- dac0996215e1c21aeef4360138eb159923ba755a — Remove XP compatibility ETW thunks    2017/7/25 6:21:03    — XP ETW thunks
- 182f32f9b5dcca678b5a6f35b3f17fc71e248f35 — Add IPv6 link local scope ID to IPEndPoint    2024/11/26 8 — dynamic if_indextoname (XP lacks it; Win7 ok) — also fixed linux host build
- 5f3f66c683b699ed3da8167b39199eed69fb8c5a — threads: Use pthread_once and InitOnceExecuteOnce    2024/ — libxml InitOnceExecuteOnce rolled back to XP x86 atomics — also linux host build
- 0dfdc0b07865610f66d95c91d2b9a404226c73a6 — gfe-relnote: Replace QuicIpAddress with a standalone imple — quiche win32_inet_ntop/pton 294 lines, XP lacks inet_ntop — also linux host build
- 9b121dfc32810250938021952aab4172a988cb56 — w32pthreads: always use Vista+ API, drop XP support    201 — ffmpeg w32pthreads XP support (condvars exist on Win7)
- 2967bf355e1b8e3e89ab0e3cd5196ec930b97182 — Merge changes from libvpx/master by cherry-pick    2016/6/ — reverts libvpx/libaom upstream cherry-picks (aom_pthread XP)
- 8cc525e82b639932870e4666c524420ff2c8536a — vpx_thread: use native windows cond var if available    20 — libvpx vpx_thread XP condvar fallback
- 110ad5835ecd66995d0e7f66dca1b90dea595f5a — thread: use native windows cond var if available    2015/1 — libwebp thread_utils XP condvar fallback (2015)
- 6680723e663ce279fcf56355ff17513f07397a53 — Implement pthread_mutex_t using SRWLOCK on Windows    2025 — libwebp thread_utils (2025 duplicate family)
- 54f23b049e06b2397722c2b3ee8e0e7bc4e6bf9b — Implement WEBP_DSP_INIT with SRWLOCK for Windows    2025/8 — libwebp WEBP_DSP_INIT: SRWLOCK -> XP
- 156edfe5361ad635c091265eb8035f2c310371d3 — Switch Windows CRYPTO_MUTEX implementation to SRWLOCK.     — boringssl CRYPTO_MUTEX: SRWLOCK -> XP critical section
- 9dadc3b6e1c2d5e2e8a3b1188c905d5541a75df7 — Replace CRYPTO_once_t on Windows with INIT_ONCE.    2016/4 — boringssl CRYPTO_once: INIT_ONCE -> XP
- e5eec6c5eb14e66e2733b135ef1c405c7e6424bf — Implement aom_once using Win32 InitOnce functions.    2018 — aom_once: InitOnce -> XP
- d77922a23d5a7615fcd42b05c0fcc5b2e2f25e94 — Implement pthread_mutex_t using SRWLOCK on Windows    2025 — libaom aom_pthread: SRWLOCK -> XP
- fdf1db62ef7ffe0f0dc77eac18c814a883fd55a0 — Implement pthread_mutex_t using SRWLOCK on Windows    2025 — libvpx vpx_pthread: SRWLOCK -> XP
- ee43805a66440d78d20310a9f822dffe87237855 — [base] Implement CPU time on Windows.    2016/6/2 2:52:39  — v8 time.cc QueryThreadCycleTime dynamic load for XP
- f5173e2286a6735cdefeda91c9dc5359dc4b23af — More accurate implementation of watched thread time for Gp — base time_win.cc QueryThreadCycleTime dynamic load for XP
- b2fc4ab8099b802de934f24adf2da6e4c863bd3c — Windows support    2018/2/20 14:48:12    b2fc4ab8099b802de — cpuinfo GetLogicalProcessorInformationEx/GetMaximumProcessorCount XP shims
- f4f0f0e2af28098ac58f8548b13d1a1f46d7c846 — Adding //third_party/abseil-cpp.    2018/4/12 17:29:41     — abseil win32_waiter -> ReactOS push locks (XP); SRWLOCK/condvar fine on Win7
- 4b298260f5327c09983083055a5775d5ce719cc1 — win: Re-enable libc++ on Windows.    2019/5/7 1:12:08    4 — libc++ thread_win32 -> ReactOS push locks (XP); SRWLOCK/INIT_ONCE fine on Win7
- 6b31cf1995f78f26e0f2fe136343ed09bd35f09b — Only initialize mutexes during DllMain    2024/9/24 6:11:5 — vulkan-loader mutex init -> XP (INIT_ONCE fine on Win7)
- 9a33184db45f00f4b929a2696229015258e66f3c — Windows: Improve pthread wrapper    2019/2/8 21:56:53    9 — dav1d win32 thread wrapper -> XP (InitOnce/condvar fine)
- 3f69e73c
- 84ee78c37199f563d107776508f5ff2aa1ff205e — Use GetFinalPathNameByHandleW to normalize file paths on Windows — older XP path normalizatione7639b7d4a81d3b818586d3bacf964a4 — Scheduler: Replace use of std::thread with marl::Thread    — marl thread.cpp -> std::thread rollback (no Win8+ APIs on upstream side)
&—  — GetFinalPathNameByHandleW -> older XP path normalization
- 1a5a84945886f72b31882b8abdd497992985595f — Call RegDeleteKeyEx directly instead of via a wrapper.     — RegDeleteKeyEx wrapped for XP
- 24a053badf908d50c49935b34908fdac68bcfda1 — Use the IFileDialog to implement SelectFileDialog on Windo — IFileDialog -> old XP file dialog
- 663525e0097433201ab3a9d374cf0398042cfb0f — Remove dynamic import of preferred UI API from kernel32.   — dynamic preferred-UI API (XP)
- 97d0c581ae51cb117d875b2a44f435a9e8f63ff0 — Remove dynamic load and call for GetUserDefaultLocaleName  — dynamic GetUserDefaultLocaleName (XP)
- 95e62b61481920eebbcaa21a25f50682cb18249b — [Win-Sandbox] Statically link SetProcessDEPPolicy.    2019 — dynamic SetProcessDEPPolicy (XP)
- a2569889cae33bb13d380f70a5f5892ec206af07 — Remove dynamic imports from Windows versioning.    2019/7/ — dynamic imports in Windows versioning (XP)
- da667f7e960637d2531cf0306fbc2137633e1773 — Make static initialization threadsafe by default    2017/1 — non-threadsafe static init default (XP era)
- f9b843b964801440b50e74b072c70e7ecb0f1921 — Cleanup/Remove Windows XP/Vista version checks from Window — sandbox XP/Vista checks + Wow64 re-add (dead for x64); also removes Wow64.h case fixup
- e89f8dfc6c46b79a391bfd6a0a8e0223eed01807 — Deprecation message for XP and Vista    2015/11/12 11:21:0 — deprecation message for XP/Vista users
- 69cb0173e70c3c29fa86982f19ec64b4a8396ceb — win: Stop setting _USING_V110_SDK71_.    2020/2/26 4:56:32 — _USING_V110_SDK71_ (XP ATL define)
- a5a75196ef378efc537edc3037c643209f6ed4e7 — Proxy GetLocaleInfo() & LocaleNameToLCID()    2025/1/8 1:1 — dynamic LocaleNameToLCID (XP; available since Vista)
- f6cca05898fa47ccb7a612032f229fcfc134bf0f — Add encrypted string support in crypto    2024/10/12 7:53: — dynamic CryptProtectMemory x2 (XP; available since Vista)
- f7379e3cb2cd2aa7109a9d5d66f79fdfc6f1df7a — Implement most ITextRangeProvider::GetAttributeValue VT_I4 — dynamic LocaleNameToLCID in AX (XP)
- e9946ec98eb14f485a85f690fb41029d492b03a2 — ICU-13027 - Merge in changes from 'branches/shawnste/worki — ICU windtfmt GetUserDefaultLocaleName (XP)
- ac869358346b76b1339422ac9766a6aeb997a51a — Move IsFullScreenMode into //ui/base/fullscreen_win.    20 — dynamic SHQueryUserNotificationState (Vista+/XP)
- 8f7a5ea7d66888d0c1d5b73e2a56e9b9de714e5e — Reland "Add Windows implementation of GetDiscoveryNetworkI — dynamic GetIfTable2/FreeMibTable (Vista+/XP)

Kept deliberately (win7-relevant, do NOT skip): c0a055bf (legacy swiftshader GLES = software WebGL on Win7), f11a6c02 (condvar fallback for base on Win7), a589a11c (WAVE audio capture fallback), f4f0f0e2-style abseil/libc++ entries are SKIPPED above, 7d18a654 (subsystem version 6.x so Win7 can load the EXE), 0d7a972e (installer min-OS so Win7 can install), 8ea9be6f (LiveTicks uses Win10 API), 88187a35 (per-OS sandbox thunk), 392e5f43 (DWM/Aero on Win7), cc3c872a (IMM32 IME), dddfcf1b (Win7 checks).
- bb4fe7af38b6a9cee46b095e18810295d18e6523 — Remove XP-specific code from file_pre_reader_win.cc. — XP branch + TouchPagesInRange + pe_image includes only; Vista+ fallback comes from 7816ff59 (kept)

| rust01 | rust-src component only (`third_party/rust-toolchain/lib/rustlib/src/rust/...`); the win64 build links the **prebuilt** rust std rlibs (`rust-toolchain/lib/rustlib/x86_64-pc-windows-msvc/lib/`), so these source edits never enter chrome.exe |
| rust02 | same as rust01 (rust-src component, not compiled into the build) |
