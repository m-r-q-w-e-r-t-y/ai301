# Contribution README - Phase II: Reproduce & Plan

## Reproduction Process

### Environment Setup
* **OS:** Ubuntu 24.04 LTS (with a modern Linux Kernel supporting eBPF/bpf_printk)
* **Setup Path:** Followed the project's standard instructions in `CONTRIBUTING.md`. 
* **Challenges & Fixes:** Encurred a minor issue with `clang` and `llvm` missing dependencies for compiling the eBPF bytecode. Resolved by running `sudo apt install clang llvm libelf-dev`.
* **Working Branch:** [https://github.com/m-r-q-w-e-r-t-y/opentelemetry-ebpf-instrumentation](https://github.com/m-r-q-w-e-r-t-y/opentelemetry-ebpf-instrumentation)

### Steps to Reproduce
Because this issue is a feature request / behavioral change for environment variables, reproduction means verifying the *current* hardcoded logging constraints:

1. Compile the repository and run the eBPF application with the debug flag enabled:
   ```bash
   export OTEL_EBPF_BPF_DEBUG=true
   ./your-ebpf-binary

```

2. Observe **Userspace stdout**. Note that eBPF logs are successfully submitted to the userspace ring buffer and printed here, cluttering application output.
3. Check the kernel trace pipe in a parallel terminal:
```bash
sudo cat /sys/kernel/debug/tracing/trace_pipe

```


4. Observe that logs are duplicated here, but lack the contextual macro data like `__FUNCTION__` name that userspace logs receive.
5. **Current Behavior:** `OTEL_EBPF_BPF_DEBUG` only accepts a boolean (`true`/`1`). There is no option to route logs *only* to `trace_pipe` and bypass the ring buffer entirely.

---

## Solution Approach (UMPIRE Framework)

### Understand

The goal is to expand the semantics of the `OTEL_EBPF_BPF_DEBUG` environment variable. Instead of a binary toggle, it should accept string/integer configurations:

* `1` / `true` (Default): Logs to both `trace_pipe` and the userspace ring buffer.
* `trace_pipe`: Skips the userspace ring buffer entirely, writing only to the kernel trace pipe.
* Additionally, when utilizing `bpf_printk`, we want to automatically include the `__FUNCTION__` name in the format string wrapper, acknowledging that older kernels may limit us to 2 remaining arguments due to the 3-argument `bpf_printk` limit.

### Match

Look at how environment variables are parsed elsewhere in the repository (e.g., config parsing files like `config.go`, `config.c`, or `env.rs` depending on the project language). Match the existing patterns for processing non-boolean environment flags.

### Plan

1. **Locate Configuration Logic:** Locate where `OTEL_EBPF_BPF_DEBUG` is read. Change its parsing logic from a strict boolean to an enum or string match (`"true"`, `"1"`, `"trace_pipe"`).
2. **Conditional Ring Buffer Submission:** Locate the eBPF ring buffer submission helper function in the C/eBPF code. Wrap the submission in an `if` statement: skip submission if the mode is strictly `trace_pipe`.
3. **Update Macro/Wrapper:** Modify the internal debug print macro (likely wrapping `bpf_printk`) to inject `__FUNCTION__` seamlessly into the formatting token.

### Review

* N/A

### Evaluate

* **Manual Verification:** Run the application with `export OTEL_EBPF_BPF_DEBUG=trace_pipe`. Verify userspace `stdout` stays entirely clean, while `sudo cat /sys/kernel/debug/tracing/trace_pipe` prints the logs correctly prefixed with the calling function's name.
* **Regression Testing:** Run the existing unit/integration test suite to verify that setting `OTEL_EBPF_BPF_DEBUG=true` still preserves legacy behavior perfectly.
