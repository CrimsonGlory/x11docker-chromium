# Linux x86_64 syscalls vs Chromium (sandbox enabled)

This table lists every Linux **x86_64** system call from Chromium’s in-tree header and whether an **outer** container seccomp filter (e.g. x11docker) should allow it when running desktop Chromium with the **Chrome sandbox enabled** (no `--no-sandbox` / `--disable-seccomp-filter-sandbox`).

## Methodology

`used?` is the **union** of static evidence that some process in a normal Linux desktop Chromium tree may legitimately need the syscall number under an outer filter:

1. **Chromium seccomp-BPF policies (primary for sandboxed children)**  Baseline policy (`sandbox/linux/seccomp-bpf-helpers/baseline_policy.*` + `syscall_sets.*`) plus process policies wired in `SandboxSeccompBPF::PolicyForSandboxType` (`sandbox/policy/linux/bpf_*_policy_linux.*`, `sandbox_seccomp_bpf_linux.cc`): renderer, GPU, network, utility, service/service_with_jit, broker, and related defaults.
2. **Browser / zygote / unsandboxed setup**  `kNoSandbox` and `kZygoteIntermediateSandbox` have **no** child BPF policy. Outer seccomp must still allow namespace/credential setup (`unshare`, `chroot`, `clone`, capability/uid syscalls, `seccomp`, `prctl`, …) and normal browser filesystem/network/process usage. Sources include `sandbox/linux/services/{credentials,namespace_sandbox,syscall_wrappers}.*` and the fact that the browser process is not under the tight child policies.
3. **Optional features**  Audio, CDM, speech recognition, Screen AI, print, hardware video decode/encode, on-device translation, and vendor GPU extras are marked `used?=true` with a **Notes** condition when a policy allows them. If you disable a feature entirely, you may be able to drop those rows for a tighter outer profile — re-validate carefully.

### Important caveats

- **`used?=false` is not a formal non-use proof.** It means this tree’s policies and setup paths do not justify allowing the call. Rare glibc/kernel fallbacks or third-party DSOs can still surprise you.
- **Do not equal outer min to renderer-only.** Under-allowing browser/zygote syscalls breaks Chromium before child sandboxes engage.
- **Print backend** (`bpf_print_backend_policy_linux.cc`) currently `Allow()`s all syscalls (TODO incomplete filter). That is **not** used to mark every row `true` (would make the table useless). If you enable print backend, treat outer seccomp as much broader or fix that policy.
- **Network process** may Allow-all when `kNetworkServiceSyscallFilter` is disabled; the table follows the fine-grained filter path plus baseline as the intended surface.
- **Parameter restrictions** (ioctl commands, prctl args, socket domains) are out of scope; this table is syscall presence only.
- **Architecture:** x86_64 only. Header generated from the kernel `syscall_64.tbl` snapshot in-tree; highest number present is **462**. Newer host-kernel syscalls beyond this list are not enumerated here.
- **Runtime `strace` is not required** for this deliverable; use it as a future refinement if a deployment still hits outer ENOSYS/SIGSYS.

## Source paths

| Role | Path |
| --- | --- |
| Syscall enumeration | `sandbox/linux/system_headers/x86_64_linux_syscalls.h` |
| Baseline + sets | `sandbox/linux/seccomp-bpf-helpers/{baseline_policy,syscall_sets,syscall_parameters_restrictions,sigsys_handlers}.*` |
| Process policies | `sandbox/policy/linux/bpf_*_policy_linux.*` |
| Policy wiring | `sandbox/policy/linux/sandbox_seccomp_bpf_linux.cc` |
| Broker | `sandbox/policy/linux/bpf_broker_policy_linux.cc`, `sandbox/linux/syscall_broker/*` |
| Namespace/credentials | `sandbox/linux/services/{credentials,namespace_sandbox,syscall_wrappers}.*` |

## Summary

| Metric | Value |
| --- | ---: |
| Total x86_64 syscalls in header | 373 |
| used?=true | 248 |
| used?=false | 125 |

## Table

| syscall | nr | used? | Notes |
| --- | ---: | --- | --- |
| `read` | 0 | true | Baseline policy (allowed).; Browser: read. |
| `write` | 1 | true | Baseline policy (allowed).; Browser: write. |
| `open` | 2 | true | Syscall broker (file access helper for sandboxed children).; Browser/zygote: open files, profiles, libraries. |
| `close` | 3 | true | Baseline policy (allowed).; Browser: close. |
| `stat` | 4 | true | Syscall broker (file access helper for sandboxed children).; Optional/vendor: ChromeOS AMD GPU policy extras (also relevant if similar drivers need them on desktop).; Browser/zygote: path stat. |
| `fstat` | 5 | true | Baseline policy (allowed). |
| `lstat` | 6 | true | Syscall broker (file access helper for sandboxed children).; Browser/zygote: path lstat. |
| `poll` | 7 | true | Baseline policy (allowed).; Browser: poll. |
| `lseek` | 8 | true | Baseline policy (allowed).; Browser: lseek. |
| `mmap` | 9 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Optional: speech recognition / SODA process.; Browser: mmap. |
| `mprotect` | 10 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser: mprotect. |
| `munmap` | 11 | true | Baseline policy (allowed).; Browser: munmap. |
| `brk` | 12 | true | Baseline policy (allowed).; Browser: heap brk. |
| `rt_sigaction` | 13 | true | Baseline policy (allowed).; Browser: signal handlers. |
| `rt_sigprocmask` | 14 | true | Baseline policy (allowed).; Browser: signal mask. |
| `rt_sigreturn` | 15 | true | Baseline policy (allowed).; Browser: signal return. |
| `ioctl` | 16 | true | Renderer/GPU/network/utility and many services (param-filtered).; Optional: audio service process (Pulse/pipewire paths, SysV IPC).; Optional: CDM (Widevine / encrypted media) process.; Optional: out-of-process hardware video decoding (VA-API/V4L2).; Optional: print compositor process.; Browser: terminal/device ioctls, GPU FD sharing, etc. |
| `pread64` | 17 | true | Baseline policy (allowed).; Browser: pread64. |
| `pwrite64` | 18 | true | Renderer and several process policies.; Optional: audio service process (Pulse/pipewire paths, SysV IPC).; Optional: CDM (Widevine / encrypted media) process.; Optional: print compositor process.; Browser: pwrite64. |
| `readv` | 19 | true | Baseline policy (allowed).; Browser: readv. |
| `writev` | 20 | true | Baseline policy (allowed).; Browser: writev. |
| `access` | 21 | true | Syscall broker (file access helper for sandboxed children).; Browser: access(2). |
| `pipe` | 22 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser: pipes. |
| `select` | 23 | true | Baseline policy (allowed).; Browser: select. |
| `sched_yield` | 24 | true | Baseline policy (allowed).; Browser: yield. |
| `mremap` | 25 | true | Renderer and several process policies.; Optional: CDM (Widevine / encrypted media) process.; Optional: Screen AI (OCR/accessibility) process.; Optional: print compositor process.; Browser: mremap. |
| `msync` | 26 | true | Browser: msync. |
| `mincore` | 27 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser: mincore. |
| `madvise` | 28 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser: madvise. |
| `shmget` | 29 | true | GPU process (System V shared memory, Linux).; Optional: audio service process (Pulse/pipewire paths, SysV IPC). |
| `shmat` | 30 | true | GPU process (System V shared memory, Linux).; Optional: audio service process (Pulse/pipewire paths, SysV IPC). |
| `shmctl` | 31 | true | GPU process (System V shared memory, Linux).; Optional: audio service process (Pulse/pipewire paths, SysV IPC). |
| `dup` | 32 | true | Baseline policy (allowed).; Browser: dup. |
| `dup2` | 33 | true | Baseline policy (allowed).; Browser: dup2. |
| `pause` | 34 | true | Baseline policy (allowed).; Browser: pause. |
| `nanosleep` | 35 | true | Baseline policy (allowed).; Browser: nanosleep. |
| `getitimer` | 36 | true | Optional: Screen AI (OCR/accessibility) process.; Browser: getitimer. |
| `alarm` | 37 | true | Optional: Screen AI (OCR/accessibility) process.; Browser: alarm. |
| `setitimer` | 38 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Optional: Screen AI (OCR/accessibility) process.; Browser: setitimer/alarm. |
| `getpid` | 39 | true | Baseline policy (allowed).; Browser: getpid. |
| `sendfile` | 40 | true | Browser: sendfile (may EPERM in children; browser can use). |
| `socket` | 41 | true | Network process (filtered domains); audio (AF_UNIX only).; Optional: audio service process (Pulse/pipewire paths, SysV IPC).; Optional/vendor: ChromeOS AMD GPU policy extras (also relevant if similar drivers need them on desktop).; Browser: sockets (IPC/local services). |
| `connect` | 42 | true | Network process; also audio (UNIX).; Optional: audio service process (Pulse/pipewire paths, SysV IPC).; Browser: connect. |
| `accept` | 43 | true | Network process.; Browser: accept. |
| `sendto` | 44 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser: sendto. |
| `recvfrom` | 45 | true | Baseline policy (allowed).; Browser: recvfrom. |
| `sendmsg` | 46 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser: sendmsg. |
| `recvmsg` | 47 | true | Baseline policy (allowed).; Browser: recvmsg. |
| `shutdown` | 48 | true | Baseline policy (allowed).; Browser: shutdown. |
| `bind` | 49 | true | Network process.; Browser: bind local sockets. |
| `listen` | 50 | true | Network process (extensions/devtools).; Browser: listen. |
| `getsockname` | 51 | true | Network process; also audio.; Optional: audio service process (Pulse/pipewire paths, SysV IPC).; Browser: getsockname. |
| `getpeername` | 52 | true | Optional: audio service process (Pulse/pipewire paths, SysV IPC).; Browser: getpeername. |
| `socketpair` | 53 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Optional/vendor: ChromeOS AMD GPU policy extras (also relevant if similar drivers need them on desktop).; Browser: Mojo/IPC socketpairs. |
| `setsockopt` | 54 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Optional: audio service process (Pulse/pipewire paths, SysV IPC).; Browser: setsockopt. |
| `getsockopt` | 55 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Optional: audio service process (Pulse/pipewire paths, SysV IPC).; Browser: getsockopt. |
| `clone` | 56 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser/zygote: fork/clone children and namespace helpers. |
| `fork` | 57 | true | Outer only: Debian `/usr/bin/chromium` is a shell launcher that forks for `uname`/pipelines before exec. Child BPF still denies fork. |
| `vfork` | 58 | true | Outer only: allow for shell/glibc spawn paths used by the Debian launcher; child BPF still denies vfork. |
| `execve` | 59 | true | Browser/zygote: launch helpers and re-exec. |
| `exit` | 60 | true | Baseline policy (allowed).; Browser: thread exit. |
| `wait4` | 61 | true | Baseline policy (allowed).; Browser/zygote: wait for children. |
| `kill` | 62 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser: signal children. |
| `uname` | 63 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Optional: audio service process (Pulse/pipewire paths, SysV IPC).; Optional: CDM (Widevine / encrypted media) process.; Optional: print compositor process.; Optional/vendor: ChromeOS AMD GPU policy extras (also relevant if similar drivers need them on desktop).; Browser: uname. |
| `semget` | 64 | true | Optional: audio service process (Pulse/pipewire paths, SysV IPC). |
| `semop` | 65 | true | Optional: audio service process (Pulse/pipewire paths, SysV IPC). |
| `semctl` | 66 | true | Optional: audio service process (Pulse/pipewire paths, SysV IPC). |
| `shmdt` | 67 | true | GPU process (System V shared memory, Linux).; Optional: audio service process (Pulse/pipewire paths, SysV IPC). |
| `msgget` | 68 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `msgsnd` | 69 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `msgrcv` | 70 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `msgctl` | 71 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `fcntl` | 72 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser: fcntl. |
| `flock` | 73 | true | Baseline policy (allowed).; Browser: flock. |
| `fsync` | 74 | true | Baseline policy (allowed).; Renderer and several process policies.; Optional: CDM (Widevine / encrypted media) process.; Optional: print compositor process.; Browser: fsync. |
| `fdatasync` | 75 | true | Baseline policy (allowed).; Renderer and several process policies.; Optional: CDM (Widevine / encrypted media) process.; Optional: print compositor process.; Browser: fdatasync. |
| `truncate` | 76 | true | Browser: truncate files. |
| `ftruncate` | 77 | true | Baseline policy (allowed).; Renderer; also GPU/CDM/audio.; Optional: audio service process (Pulse/pipewire paths, SysV IPC).; Optional: CDM (Widevine / encrypted media) process.; Browser: ftruncate. |
| `getdents` | 78 | true | GPU; also network/audio/speech/broker-related paths.; Optional: audio service process (Pulse/pipewire paths, SysV IPC).; Optional: speech recognition / SODA process.; Browser: directory listing. |
| `getcwd` | 79 | true | Browser: cwd. |
| `chdir` | 80 | true | Browser: chdir. |
| `fchdir` | 81 | true | Browser: fchdir. |
| `rename` | 82 | true | Syscall broker (file access helper for sandboxed children).; Browser: atomic profile updates. |
| `mkdir` | 83 | true | Syscall broker (file access helper for sandboxed children).; Browser: profile and cache dirs. |
| `rmdir` | 84 | true | Syscall broker (file access helper for sandboxed children).; Browser: cleanup. |
| `creat` | 85 | true | Browser: create files. |
| `link` | 86 | true | Browser: hard links (rare). |
| `unlink` | 87 | true | Syscall broker (file access helper for sandboxed children).; Browser: cleanup. |
| `symlink` | 88 | true | Browser: may create symlinks. |
| `readlink` | 89 | true | Syscall broker (file access helper for sandboxed children).; Optional/vendor: ChromeOS AMD GPU policy extras (also relevant if similar drivers need them on desktop).; Browser: resolve links / proc paths. |
| `chmod` | 90 | true | Browser: file modes. |
| `fchmod` | 91 | true | Browser: fchmod. |
| `chown` | 92 | true | Browser: may adjust ownership in profile paths. |
| `fchown` | 93 | true | Browser: fchown. |
| `lchown` | 94 | true | Browser: lchown. |
| `umask` | 95 | true | Browser: umask for created files. |
| `gettimeofday` | 96 | true | Baseline policy (allowed).; Browser: gettimeofday. |
| `getrlimit` | 97 | true | Renderer/utility/service/CDM/print compositor.; Optional: CDM (Widevine / encrypted media) process.; Optional: print compositor process.; Browser: resource limits. |
| `getrusage` | 98 | true | Browser: getrusage. |
| `sysinfo` | 99 | true | Renderer/GPU/network/utility and others.; Optional: CDM (Widevine / encrypted media) process.; Optional: Screen AI (OCR/accessibility) process.; Optional: out-of-process hardware video decoding (VA-API/V4L2).; Optional: print compositor process.; Optional/vendor: ChromeOS AMD GPU policy extras (also relevant if similar drivers need them on desktop).; Browser: sysinfo. |
| `times` | 100 | true | Renderer/utility/service/CDM/print compositor.; Optional: CDM (Widevine / encrypted media) process.; Optional: print compositor process.; Browser: times. |
| `ptrace` | 101 | true | Optional: Crashpad / debugging attach paths from browser. |
| `getuid` | 102 | true | Baseline policy (allowed).; Browser: getuid. |
| `syslog` | 103 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `getgid` | 104 | true | Baseline policy (allowed).; Browser: getgid. |
| `setuid` | 105 | true | Browser/zygote: privilege drop (setuid sandbox / credentials). |
| `setgid` | 106 | true | Browser/zygote: privilege drop. |
| `geteuid` | 107 | true | Baseline policy (allowed).; Browser: geteuid. |
| `getegid` | 108 | true | Baseline policy (allowed).; Browser: getegid. |
| `setpgid` | 109 | true | Browser: setpgid. |
| `getppid` | 110 | true | Baseline policy (allowed).; Browser: getppid. |
| `getpgrp` | 111 | true | Browser: getpgrp. |
| `setsid` | 112 | true | Browser: setsid. |
| `setreuid` | 113 | true | Browser/zygote: privilege drop. |
| `setregid` | 114 | true | Browser/zygote: privilege drop. |
| `getgroups` | 115 | true | Baseline policy (allowed).; Browser: getgroups. |
| `setgroups` | 116 | true | Browser/zygote: privilege drop. |
| `setresuid` | 117 | true | Browser/zygote: privilege drop. |
| `getresuid` | 118 | true | Baseline policy (allowed).; Browser: getresuid. |
| `setresgid` | 119 | true | Browser/zygote: privilege drop. |
| `getresgid` | 120 | true | Baseline policy (allowed).; Browser: getresgid. |
| `getpgid` | 121 | true | Browser: getpgid. |
| `setfsuid` | 122 | true | Browser/zygote: privilege drop. |
| `setfsgid` | 123 | true | Browser/zygote: privilege drop. |
| `getsid` | 124 | true | Baseline policy (allowed).; Browser: getsid. |
| `capget` | 125 | true | Baseline policy (allowed).; Browser/zygote: capability drop. |
| `capset` | 126 | true | Browser/zygote: capability drop. |
| `rt_sigpending` | 127 | true | Browser: may query pending signals. |
| `rt_sigtimedwait` | 128 | true | Baseline policy (allowed).; Browser: rt_sigtimedwait. |
| `rt_sigqueueinfo` | 129 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `rt_sigsuspend` | 130 | true | Browser: may use sigsuspend paths. |
| `sigaltstack` | 131 | true | Baseline policy (allowed).; Browser: alternate signal stacks. |
| `utime` | 132 | true | Browser: timestamps. |
| `mknod` | 133 | true | Browser: rare device/fifo creation. |
| `uselib` | 134 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `personality` | 135 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `ustat` | 136 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `statfs` | 137 | true | Browser: filesystem info. |
| `fstatfs` | 138 | true | Baseline policy (allowed).; Browser: fstatfs. |
| `sysfs` | 139 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `getpriority` | 140 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser: priority. |
| `setpriority` | 141 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser: priority. |
| `sched_setparam` | 142 | true | Browser: sched_setparam. |
| `sched_getparam` | 143 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser: sched_getparam. |
| `sched_setscheduler` | 144 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Optional: out-of-process hardware video decoding (VA-API/V4L2).; Optional/vendor: ChromeOS AMD GPU policy extras (also relevant if similar drivers need them on desktop).; Optional/vendor: ChromeOS Intel GPU policy.; Optional/vendor: ChromeOS NVIDIA GPU policy.; Optional/vendor: ChromeOS virtio GPU policy.; Browser: scheduler policy. |
| `sched_getscheduler` | 145 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser: scheduler policy. |
| `sched_get_priority_max` | 146 | true | Renderer.; Browser: sched priority range. |
| `sched_get_priority_min` | 147 | true | Renderer.; Browser: sched priority range. |
| `sched_rr_get_interval` | 148 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `mlock` | 149 | true | Baseline policy (allowed).; Browser: mlock. |
| `munlock` | 150 | true | Baseline policy (allowed).; Browser: munlock. |
| `mlockall` | 151 | true | Browser: rare mlockall. |
| `munlockall` | 152 | true | Browser: rare munlockall. |
| `vhangup` | 153 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `modify_ldt` | 154 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `pivot_root` | 155 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `_sysctl` | 156 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `prctl` | 157 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Optional: speech recognition / SODA process.; Browser/zygote: dumpable, no_new_privs, speculation, etc. |
| `arch_prctl` | 158 | true | Browser process (x86_64 TLS / arch setup via glibc). |
| `adjtimex` | 159 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `setrlimit` | 160 | true | Renderer (WebAssembly address-space adjust).; Browser: resource limits. |
| `chroot` | 161 | true | Browser/zygote: empty-dir chroot sandbox engagement. |
| `sync` | 162 | true | Browser: sync (rare). |
| `acct` | 163 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `settimeofday` | 164 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `mount` | 165 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `umount2` | 166 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `swapon` | 167 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `swapoff` | 168 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `reboot` | 169 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `sethostname` | 170 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `setdomainname` | 171 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `iopl` | 172 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `ioperm` | 173 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `create_module` | 174 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `init_module` | 175 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `delete_module` | 176 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `get_kernel_syms` | 177 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `query_module` | 178 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `quotactl` | 179 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `nfsservctl` | 180 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `getpmsg` | 181 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `putpmsg` | 182 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `afs_syscall` | 183 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `tuxcall` | 184 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `security` | 185 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `gettid` | 186 | true | Baseline policy (allowed).; Browser: gettid. |
| `readahead` | 187 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `setxattr` | 188 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `lsetxattr` | 189 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `fsetxattr` | 190 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `getxattr` | 191 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `lgetxattr` | 192 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `fgetxattr` | 193 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `listxattr` | 194 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `llistxattr` | 195 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `flistxattr` | 196 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `removexattr` | 197 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `lremovexattr` | 198 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `fremovexattr` | 199 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `tkill` | 200 | true | Baseline/BPFBase (allowed or arg-restricted allow). |
| `time` | 201 | true | Baseline policy (allowed).; Browser: time. |
| `futex` | 202 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Optional: Screen AI (OCR/accessibility) process.; Browser: futex. |
| `sched_setaffinity` | 203 | true | GPU (restricted to self); also HW video decode.; Optional: out-of-process hardware video decoding (VA-API/V4L2).; Optional/vendor: ChromeOS AMD GPU policy extras (also relevant if similar drivers need them on desktop).; Browser: CPU affinity. |
| `sched_getaffinity` | 204 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser: CPU affinity. |
| `set_thread_area` | 205 | true | Browser/glibc: TLS (legacy path). |
| `io_setup` | 206 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `io_destroy` | 207 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `io_getevents` | 208 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `io_submit` | 209 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `io_cancel` | 210 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `get_thread_area` | 211 | true | Browser/glibc: TLS (legacy path). |
| `lookup_dcookie` | 212 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `epoll_create` | 213 | true | Baseline policy (allowed).; Browser: epoll. |
| `epoll_ctl_old` | 214 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `epoll_wait_old` | 215 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `remap_file_pages` | 216 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `getdents64` | 217 | true | GPU; also network/audio/speech.; Optional: speech recognition / SODA process.; Optional: out-of-process hardware video decoding (VA-API/V4L2).; Browser: directory listing. |
| `set_tid_address` | 218 | true | Browser/glibc: threading. |
| `restart_syscall` | 219 | true | Baseline policy (allowed).; Kernel restart helper. |
| `semtimedop` | 220 | true | Optional: audio service process (Pulse/pipewire paths, SysV IPC). |
| `fadvise64` | 221 | true | Baseline policy (allowed).; Network (POSIX_FADV_WILLNEED); also baseline set. |
| `timer_create` | 222 | true | Browser: POSIX timers. |
| `timer_settime` | 223 | true | Browser: POSIX timers. |
| `timer_gettime` | 224 | true | Browser: POSIX timers. |
| `timer_getoverrun` | 225 | true | Browser: POSIX timers. |
| `timer_delete` | 226 | true | Browser: POSIX timers. |
| `clock_settime` | 227 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `clock_gettime` | 228 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser: clocks. |
| `clock_getres` | 229 | true | Renderer (V8).; Browser: clocks. |
| `clock_nanosleep` | 230 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser: clocks. |
| `exit_group` | 231 | true | Baseline policy (allowed).; Browser: process exit. |
| `epoll_wait` | 232 | true | Baseline policy (allowed).; Browser: epoll. |
| `epoll_ctl` | 233 | true | Baseline policy (allowed).; Browser: epoll. |
| `tgkill` | 234 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser: tgkill. |
| `utimes` | 235 | true | Browser: timestamps. |
| `vserver` | 236 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `mbind` | 237 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `set_mempolicy` | 238 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `get_mempolicy` | 239 | true | Optional: Screen AI (OCR/accessibility) process. |
| `mq_open` | 240 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `mq_unlink` | 241 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `mq_timedsend` | 242 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `mq_timedreceive` | 243 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `mq_notify` | 244 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `mq_getsetattr` | 245 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `kexec_load` | 246 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `waitid` | 247 | true | Baseline policy (allowed).; Browser/zygote: waitid. |
| `add_key` | 248 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `request_key` | 249 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `keyctl` | 250 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `ioprio_set` | 251 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `ioprio_get` | 252 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `inotify_init` | 253 | true | Network process (inotify set except add_watch via broker).; Browser: file watching. |
| `inotify_add_watch` | 254 | true | Syscall broker (file access helper for sandboxed children).; Browser: file watching. |
| `inotify_rm_watch` | 255 | true | Network process (inotify set).; Browser: file watching. |
| `migrate_pages` | 256 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `openat` | 257 | true | Syscall broker (file access helper for sandboxed children).; Browser/zygote: open files. |
| `mkdirat` | 258 | true | Syscall broker (file access helper for sandboxed children).; Browser: mkdirat. |
| `mknodat` | 259 | true | Browser: mknodat. |
| `fchownat` | 260 | true | Browser: fchownat. |
| `futimesat` | 261 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `newfstatat` | 262 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Syscall broker (file access helper for sandboxed children).; Browser/zygote: fstatat. |
| `unlinkat` | 263 | true | Syscall broker (file access helper for sandboxed children).; Browser: cleanup. |
| `renameat` | 264 | true | Syscall broker (file access helper for sandboxed children).; Browser: renameat. |
| `linkat` | 265 | true | Browser: linkat. |
| `symlinkat` | 266 | true | Browser: symlinkat. |
| `readlinkat` | 267 | true | Syscall broker (file access helper for sandboxed children).; Browser: readlinkat. |
| `fchmodat` | 268 | true | Browser: fchmodat. |
| `faccessat` | 269 | true | Syscall broker (file access helper for sandboxed children).; Browser: faccessat. |
| `pselect6` | 270 | true | Baseline policy (allowed).; Browser: pselect6. |
| `ppoll` | 271 | true | Baseline policy (allowed).; Browser: ppoll. |
| `unshare` | 272 | true | Browser/zygote: user/pid/net namespace sandbox setup. |
| `set_robust_list` | 273 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser: robust futex lists. |
| `get_robust_list` | 274 | true | Baseline policy (allowed).; Browser: robust futex lists. |
| `splice` | 275 | true | Browser: splice. |
| `tee` | 276 | true | Browser: tee. |
| `sync_file_range` | 277 | true | Baseline policy (allowed). |
| `vmsplice` | 278 | true | Browser: vmsplice. |
| `move_pages` | 279 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `utimensat` | 280 | true | Browser: timestamps. |
| `epoll_pwait` | 281 | true | Baseline policy (allowed).; Browser: epoll. |
| `signalfd` | 282 | true | Outer only: x11docker PID1 (catatonit/tini) needs signalfd; Chromium child BPF may still deny. |
| `timerfd_create` | 283 | true | Browser: timerfd. |
| `eventfd` | 284 | true | Baseline policy (allowed).; Browser: eventfd. |
| `fallocate` | 285 | true | GPU process (non-ChromeOS path).; Optional: audio service process (Pulse/pipewire paths, SysV IPC).; Optional: CDM (Widevine / encrypted media) process.; Browser: fallocate. |
| `timerfd_settime` | 286 | true | Browser: timerfd. |
| `timerfd_gettime` | 287 | true | Browser: timerfd. |
| `accept4` | 288 | true | Network process.; Browser: accept4. |
| `signalfd4` | 289 | true | Outer only: x11docker PID1 (catatonit/tini) needs signalfd4; Chromium child BPF may still deny. |
| `eventfd2` | 290 | true | Baseline policy (allowed).; Browser: eventfd2. |
| `epoll_create1` | 291 | true | Baseline policy (allowed).; Browser: epoll. |
| `dup3` | 292 | true | Baseline policy (allowed).; Browser: dup3. |
| `pipe2` | 293 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser: pipe2. |
| `inotify_init1` | 294 | true | Network process (inotify set).; Browser: file watching. |
| `preadv` | 295 | true | Browser: preadv. |
| `pwritev` | 296 | true | Browser: pwritev. |
| `rt_tgsigqueueinfo` | 297 | true | Baseline/BPFBase (allowed or arg-restricted allow). |
| `perf_event_open` | 298 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `recvmmsg` | 299 | true | Baseline policy (allowed).; Browser: recvmmsg. |
| `fanotify_init` | 300 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `fanotify_mark` | 301 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `prlimit64` | 302 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Optional: CDM (Widevine / encrypted media) process.; Optional: speech recognition / SODA process.; Optional: Screen AI (OCR/accessibility) process.; Browser: prlimit. |
| `name_to_handle_at` | 303 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `open_by_handle_at` | 304 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `clock_adjtime` | 305 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `syncfs` | 306 | true | Browser: syncfs (rare). |
| `sendmmsg` | 307 | true | Network process.; Browser: sendmmsg. |
| `setns` | 308 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `getcpu` | 309 | true | Optional: Screen AI (OCR/accessibility) process. |
| `process_vm_readv` | 310 | true | Optional: Crashpad / process introspection. |
| `process_vm_writev` | 311 | true | Optional: rare debugger/helper paths. |
| `kcmp` | 312 | true | Optional: out-of-process hardware video decoding (VA-API/V4L2).; Optional/vendor: ChromeOS AMD GPU policy extras (also relevant if similar drivers need them on desktop).; Optional: GPU/HW-decode kcmp; browser may not need it. |
| `finit_module` | 313 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `sched_setattr` | 314 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `sched_getattr` | 315 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `renameat2` | 316 | true | Browser: renameat2. |
| `seccomp` | 317 | true | Browser/zygote: install child seccomp-BPF filters. |
| `getrandom` | 318 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser: getrandom. |
| `memfd_create` | 319 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser: Mojo/shared memory. |
| `kexec_file_load` | 320 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `bpf` | 321 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `execveat` | 322 | true | Browser: execveat if used by helpers. |
| `userfaultfd` | 323 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `membarrier` | 324 | true | Optional: on-device translation process.; Browser: membarrier (threading/rseq registration). |
| `mlock2` | 325 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `copy_file_range` | 326 | true | Browser: efficient file copy if available. |
| `preadv2` | 327 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `pwritev2` | 328 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `pkey_mprotect` | 329 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser/V8 PKU if enabled. |
| `pkey_alloc` | 330 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser/V8 PKU if enabled. |
| `pkey_free` | 331 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser/V8 PKU if enabled. |
| `statx` | 332 | true | Browser/glibc may issue statx; baseline forces ENOSYS fallback — outer must not kill. |
| `io_pgetevents` | 333 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `rseq` | 334 | true | Baseline/BPFBase (allowed or arg-restricted allow).; Browser/glibc: restartable sequences. |
| `pidfd_send_signal` | 424 | true | Optional: modern process signaling via pidfd. |
| `io_uring_setup` | 425 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `io_uring_enter` | 426 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `io_uring_register` | 427 | false | No evidence in Chromium BPF policies or sandbox setup; admin/privileged/debug class — safe default-deny candidate. |
| `open_tree` | 428 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `move_mount` | 429 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `fsopen` | 430 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `fsconfig` | 431 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `fsmount` | 432 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `fspick` | 433 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `pidfd_open` | 434 | true | Browser may try pidfd_open; baseline ENOSYS — allow for fallback. |
| `clone3` | 435 | true | Browser/zygote/glibc may attempt clone3 (baseline returns ENOSYS to force clone); allow so libc can fall back. |
| `close_range` | 436 | true | Browser: close_range (glibc/posix_spawn helpers). |
| `openat2` | 437 | true | Browser may use modern openat2 if glibc/kernel paths do. |
| `pidfd_getfd` | 438 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `faccessat2` | 439 | true | Syscall broker (file access helper for sandboxed children).; Browser: faccessat2. |
| `process_madvise` | 440 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `epoll_pwait2` | 441 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `mount_setattr` | 442 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `landlock_create_ruleset` | 444 | true | Optional Landlock GPU/path restrictions (sandbox wrappers). |
| `landlock_add_rule` | 445 | true | Optional Landlock GPU/path restrictions. |
| `landlock_restrict_self` | 446 | true | Optional Landlock GPU/path restrictions. |
| `memfd_secret` | 447 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `process_mrelease` | 448 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `futex_waitv` | 449 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `set_mempolicy_home_node` | 450 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `cachestat` | 451 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `fchmodat2` | 452 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `map_shadow_stack` | 453 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `futex_wake` | 454 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `futex_wait` | 455 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `futex_requeue` | 456 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `statmount` | 457 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `listmount` | 458 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `lsm_get_self_attr` | 459 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `lsm_set_self_attr` | 460 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `lsm_list_modules` | 461 | false | Not allowed by baseline/core desktop policies and not in browser/zygote setup allowlist (static analysis). |
| `mseal` | 462 | true | Baseline policy (allowed).; Browser/baseline: mseal. |

---

Generated by `tools/linux_syscall_audit/syscall_audit.py`. Re-run after sandbox policy changes.
