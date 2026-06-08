# Contribution [#]: Decouple eBPF Debug Logging viaOTEL_EBPF_BPF_DEBUG
**Contribution Number:** [1 / 2 / 3]
**Student:** [Your Name]
**Issue:** [GitHub issue link / RFC discussion link]
**Status:** Phase I - In Progress
# Why I Chose This Issue
I chose to propose and implement this change because I am highly interested in observability telemetry and the performance characteristics of eBPF. Debugging eBPF programs often requires a delicate balance between extracting deep kernel insights and maintaining minimal overhead. Currently, mixing kernel trace outputs with userspace application logs can create noise and complicate log parsing.
This issue allows me to dive deep into the data pathways between the Linux kernel and userspace (specifically ring buffers vs. tracepipes). It aligns perfectly with my goals of understanding advanced Linux tracing, OpenTelemetry standards, and how to write clean, maintainable systems-level configuration code. I hope to learn more about the upstream architecture of OpenTelemetry’s eBPF instrumentation and how to manage kernel compatibility constraints across different deployment environments.
# Understanding the Issue
### Problem Description
Currently, the OTEL_EBPF_BPF_DEBUG configuration environment variable forces a tightly coupled logging strategy. When debugging is enabled, log messages are simultaneously written to the kernel's trace_pipe and submitted to the userspace ring buffer. This behavior pollutes the userspace application output with kernel-level noise, making it difficult to isolate eBPF telemetry from general application execution logic. Furthermore, formatting consistency is lost because userspace logs include contextual data (like function names) that standard trace_pipe outputs lack.
### Expected Behavior
The OTEL_EBPF_BPF_DEBUG variable should support granular semantic choices rather than acting as a strict boolean toggle:
* default / true / 1: Retain the fallback behavior of duplicating print statements to both trace_pipe and the userspace ring buffer.
* trace_pipe: Route eBPF debug logs *strictly* to the kernel trace pipe, skipping the userspace ring buffer entirely. This keeps userspace standard output clean and removes character limits associated with standard ring buffer message payloads.

⠀Additionally, regardless of the routing target, the eBPF logging macro should automatically append contextual metadata (such as the current function name via __FUNCTION__) to make the kernel stream as informative as the userspace stream.
### Current Behavior
When OTEL_EBPF_BPF_DEBUG is active, messages are aggressively pushed to both targets simultaneously. There is no isolated toggle to choose one interface over the other, nor do the raw trace_pipe prints consistently contain the execution context prefix (%s: format wrapper) out-of-the-box.
### Affected Components
* **Macro Definitions / Logging Headers:** The internal eBPF wrapper macros handling bpf_printk and ring buffer submissions.
* **Configuration Parser:** The subsystem in the Go/C environment responsible for initializing the BPF maps and evaluating OTEL_EBPF_BPF_DEBUG.
* **Userspace Ring Buffer Consumer:** Logic handling incoming debug events from the kernel ring buffer.

⠀Reproduction Process
### Environment Setup
* *Setup Notes:* Configured a local Linux development VM running a modern kernel (e.g., 5.15+) with clang, llvm, and libbpf installed.
* *Challenges:* Enforcing argument limits during BPF compilation verification. Older kernels strictly limit bpf_printk to 3 variables total, meaning adding __FUNCTION__ and an extra format string consumes slots that would otherwise be used by the developer's raw arguments.

⠀Steps to Reproduce
1 Enable eBPF debugging by setting OTEL_EBPF_BPF_DEBUG=1.
2 Run the instrumented application.
3 Observe that logs populate both standard userspace stdout and /sys/kernel/debug/tracing/trace_pipe.
4 Attempt to pass trace_pipe as a distinct configuration string and observe that it is evaluated either as a truthy boolean fallback or throws a configuration error.

⠀Reproduction Evidence
* **Commit showing reproduction:** [Link to commit in your fork]
* **Screenshots/logs:** N/A (Behavior verified via code review of macro expansions).
* **My findings:** Confirmed that the current macro design lacks conditional compilation or runtime checks to bypass the ring buffer push when bpf_printk triggers.

⠀Solution Approach
### Analysis
The root cause is a binary design assumption regarding the debug state. Because OTEL_EBPF_BPF_DEBUG is treated as a boolean toggle, the eBPF program cannot know at runtime (or load time) that the developer explicitly wants to suppress the userspace ring buffer submission. Moreover, appending __FUNCTION__ modifies the variadic argument count for bpf_printk.
### Proposed Solution
Update the internal configuration loading mechanics to accept string tokens (true, 1, trace_pipe). If trace_pipe is selected, a specific BPF configuration map flag or a read-only global variable (e.g., const volatile bool skip_ring_buffer) will be set at load time. The logging macro will evaluate this flag to conditionally skip ring buffer submission.
To address the contextual formatting, wrap bpf_printk in a macro that injects __FUNCTION__.
**Important Caveat:** Injecting __FUNCTION__ and its corresponding %s: format specifier consumes 2 of the available arguments for bpf_printk. On kernels where bpf_printk supports a maximum of 3 format arguments, this restricts the developer to **1 custom argument** (down from 3). This trade-off must be clearly documented in the project's README.
### Implementation Plan
Using UMPIRE framework (adapted):
**Understand:** Provide an isolated runtime logging mechanism to trace_pipe without forcing userspace pollution, while maintaining functional context in the log strings despite strict BPF argument limits.
**Match:** Look at how other OpenTelemetry environment variables handle advanced string/enum configurations rather than simple booleans, and how existing global constants are injected into BPF bytecode using libbpf skeletons.
**Plan:**
1 Update configuration handlers to recognize OTEL_EBPF_BPF_DEBUG=trace_pipe.
2 Define a read-only configuration variable in the BPF program (bool switch_trace_only).
3 Refactor the debug logging macro to evaluate switch_trace_only before pushing data to the userspace ring buffer.
4 Update the bpf_printk wrapper macro to inject __FUNCTION__.
5 Update documentation/README regarding the reduced parameter limit (down to 2 or 1 arguments depending on target kernel version) when debugging is activated.

⠀**Implement:** [Link to your branch/commits as you work]
**Review:** Ensure compliance with the project's C/Go code styling rules and verify BPF verification passes on targeted kernel variations.
**Evaluate:** Run verification scripts to ensure that when trace_pipe mode is active, the userspace process receives zero debug telemetry while cat /sys/kernel/debug/tracing/trace_pipe prints beautifully formatted, context-aware strings.
# Testing Strategy
### Unit Tests
* [ ] Test case 1: Verify config parser handles 1, true, and trace_pipe accurately.
* [ ] Test case 2: Assert that passing an invalid option defaults safely to disabled or standard true behavior.

⠀Integration Tests
* [ ] Integration scenario 1: Run with OTEL_EBPF_BPF_DEBUG=1 and assert messages exist in both streams.
* [ ] Integration scenario 2: Run with OTEL_EBPF_BPF_DEBUG=trace_pipe and assert zero debug messages enter the userspace buffer.

⠀Manual Testing
* Manually trace macro expansion output with clang -E to confirm that __FUNCTION__ is properly injected and does not break the compiler on max-argument BPF invocations.

⠀Implementation Notes
### Week [X] Progress
* Submitted RFC proposal regarding the variable semantics.
* Map design drafted out to pass configuration data down to the kernel probe layer seamlessly.

⠀Code Changes
* **Files modified:** [List of files, e.g., pkg/ebpf/c/logging.h, pkg/config/config.go]
* **Key commits:** [Links to important commits]
* **Approach decisions:** Decided to use a global read-only variable for tracking the config state inside the kernel because it features faster access times than doing map lookups during high-frequency trace events.

⠀Pull Request
**PR Link:** [GitHub PR URL when submitted]
**PR Description:** [Draft or final PR description - much of the content above can be adapted]
**Maintainer Feedback:**
* [Date]: [Summary of feedback received]

⠀**Status:** [Awaiting review / Iterating / Approved / Merged]
# Learnings & Reflections
### Technical Skills Gained
* Deepened understanding of BPF verification boundaries and string formatting limits within the Linux kernel.
* Gained experience creating flexible environment configurations that interface between system daemons and kernel-space probes.

⠀Challenges Overcome
* Overcoming the BPF argument ceiling required cautious macro planning, finding a way to safely append context without failing compilation step checks for end-users running older kernels.

⠀What I'd Do Differently Next Time
[Reflection on your process]
# Resources Used
* ~[OpenTelemetry eBPF Instrumentation Repository](https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation)~
* ~[Bpf-helpers\(7\) Linux Manual Page for bpf_printk](https://man7.org/linux/man-pages/man7/bpf-helpers.7.html)~
* ~[Libbpf Global Variables Documentation](https://github.com/libbpf/libbpf)~
