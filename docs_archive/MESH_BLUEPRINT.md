> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Sporkle Mesh Manager — Junk Network Blueprint (v0.1)

> Goal: Give Sparkle an auto-discovering, topology-aware, self-healing mesh that runs on whatever junk you plug in (CPU, NVIDIA/AMD GPUs, iGPUs, Jetsons, oddballs) and schedules work opportunistically with Pythonic-Fortran ergonomics.

---

## 0) Design Tenets

* **Device agnostic, topology aware**: We never assume a single primary GPU; we build a mesh.
* **Pythonic Fortran**: Clean names, keyword args, modules over macros, array ops over hand loops.
* **Graceful degradation**: If P2P/UCX/NVLINK/ROCm-P2P isn't available, we fall back to pinned host memory or shared memory without user intervention.
* **Self-healing**: Device failure → reweight graph, reshard work, continue.
* **Explainable scheduling**: Introspection APIs report why we made a decision.

---

## 1) High-Level Architecture

```
Sparkle Context
 ├─ Device Registry (discovery + profiling)
 │   ├─ CPU Backend (OpenMP)
 │   ├─ NVIDIA Backend (CUDA via C-interop or OpenACC)
 │   ├─ AMD Backend (HIP/ROCm via C-interop or OpenACC)
 │   ├─ iGPU Backend (Level Zero / OpenCL via C-interop)
 │   └─ Ext plugs (FPGA/OpenCL)
 ├─ Mesh Builder (topology graph)
 │   ├─ Capability Matrix (bandwidth, latency, P2P flags)
 │   ├─ Transfer Planner (direct, staged, ring/tree/mesh)
 │   └─ Health Monitor (QoS, failures)
 ├─ Orchestrator (work partitioning + scheduling)
 │   ├─ Cost Model (compute cost + transfer cost)
 │   ├─ Work Queues (per device and global)
 │   └─ Collectives (all-reduce, broadcast, scatter/gather)
 └─ Introspection (telemetry + trace + replay)
```

---

## 2) Core Data Types (Fortran 2008 style)

```fortran
module sporkle_types
  implicit none
  private

  integer, parameter :: rk32 = selected_real_kind(6), rk64 = selected_real_kind(15)

  type :: device_capabilities
     character(len=:), allocatable :: kind   ! "cpu", "nvidia", "amd", "igpu", "fpga", ...
     integer :: cores
     integer :: sm_count          ! streaming multiprocessors, if GPU
     integer :: vram_mb
     integer :: unified_mem       ! boolean 0/1
     real(rk64) :: peak_gflops
     real(rk64) :: mem_bw_gbs
     logical :: p2p_direct        ! device→device direct
     logical :: uvm_supported     ! unified virtual memory
  end type

  type :: device_handle
     integer :: id
     type(device_capabilities) :: caps
     type(c_ptr) :: native        ! C handle (cudaDevice_t/hipDevice_t/OpenMP device idx)
     logical :: healthy
  end type

  type :: link_metrics
     integer :: src_id, dst_id
     real(rk64) :: bw_gbs
     real(rk64) :: latency_us
     logical :: direct
  end type

  type :: mesh_topology
     type(device_handle), allocatable :: devices(:)
     type(link_metrics), allocatable :: links(:)
  end type

  type :: schedule_choice
     integer, allocatable :: shards(:)   ! per-device shard sizes
     real(rk64) :: est_ms
  end type

  public :: device_capabilities, device_handle, link_metrics, mesh_topology, schedule_choice, rk32, rk64
end module
```

---

## 3) Discovery + Profiling

### 3.1 Device Discovery (pseudo-flow)

1. Enumerate CPU (always present).
2. Try CUDA → list devices; probe attributes.
3. Try HIP/ROCm → same.
4. Try Level Zero/OpenCL for iGPUs.
5. Optional plugin hooks (user-provided discovery subroutines).

### 3.2 Microbenchmarks (fast, cached)

* **Compute probe**: tiny GEMM/conv kernels → peak/sustained GFLOPs.
* **Mem probe**: host↔device (H2D/D2H), device↔device P2P if supported.
* **Latency probe**: ping micro-kernel.
* Cache in `~/.sparkle/profile.json` keyed by PCI IDs + driver versions.

### 3.3 Fortran-side API

```fortran
module sporkle_discovery
  use sporkle_types
  implicit none
  private
  public :: scan_devices, profile_links
contains
  function scan_devices() result(mesh)
    type(mesh_topology) :: mesh
    ! Allocate, fill mesh%devices from backends.
  end function

  subroutine profile_links(mesh)
    type(mesh_topology), intent(inout) :: mesh
    ! Fill mesh%links by measuring bw/latency, mark direct P2P.
  end subroutine
end module
```

---

## 4) Mesh Builder

* Build a **graph** `G(V,E)` where `V=devices`, `E=links` with weights `(bw, latency, reliability)`.
* Maintain **adjacency matrix** for fast collective planning.
* Annotate edges with **routes** (direct, staged via host, staged via fastest peer).
* Update online with EMA smoothing as loads vary (adaptive bw/lat).

```fortran
module sporkle_mesh
  use sporkle_types
  implicit none
  private
  public :: build_mesh, best_route
contains
  function build_mesh() result(mesh)
    type(mesh_topology) :: mesh
    mesh = scan_devices()
    call profile_links(mesh)
  end function

  subroutine best_route(mesh, src, dst, path_ids)
    type(mesh_topology), intent(in) :: mesh
    integer, intent(in) :: src, dst
    integer, allocatable, intent(out) :: path_ids(:)
    ! Dijkstra over latency, tie-break on inverse bandwidth; prefer direct if available.
  end subroutine
end module
```

---

## 5) Orchestrator (Cost Model + Scheduler)

### 5.1 Cost Model

`T_total = T_compute(device, shard) + T_transfer(in) + T_transfer(out) + T_sync`

* `T_compute`: from sustained GFLOPs model + empirical kernel tables.
* `T_transfer`: size / bw + latency across chosen route.
* Penalize devices with low reliability or high recent queue depth.

### 5.2 Sharding Strategies

* **Data parallel** (batch-split) for GEMM/ML ops first.
* **Operator parallel** (layer/column split) later.
* Auto-pick sharding by minimizing `Σ T_total` subject to device memory constraints.

### 5.3 Scheduler API

```fortran
module sporkle_schedule
  use sporkle_types
  implicit none
  private
  public :: plan_shards, dispatch_kernel
contains
  function plan_shards(mesh, work_size) result(choice)
    type(mesh_topology), intent(in) :: mesh
    integer, intent(in) :: work_size
    type(schedule_choice) :: choice
    ! Greedy or ILP-lite: allocate shards proportional to compute score, adjust for transfer costs.
  end function

  subroutine dispatch_kernel(mesh, kernel, args, choice)
    type(mesh_topology), intent(in) :: mesh
    ! kernel: procedure pointer wrapped in sporkle_kernel
    ! args:   opaque arg bundle
    type(schedule_choice), intent(in) :: choice
    ! Launch on devices, set up transfers per route, handle sync & reduction if requested.
  end subroutine
end module
```

---

## 6) Collectives (Mesh-Native)

* `all_reduce(sum/max/mean)`, `broadcast`, `scatter`, `gather`.
* Choose algorithm by topology and tensor size:

  * **Small**: tree-based (latency-optimized).
  * **Large**: ring/mesh (bandwidth-optimized), P2P if possible, fallback via host.

```fortran
module sporkle_collectives
  use sporkle_types
  implicit none
  private
  public :: all_reduce
contains
  subroutine all_reduce(mesh, buf, op)
    type(mesh_topology), intent(in) :: mesh
    class(*), intent(inout) :: buf
    integer, intent(in) :: op
    ! Select ring/tree; use best_route for each hop.
  end subroutine
end module
```

---

## 7) Pythonic Fortran API (Ergonomics Layer)

```fortran
! Example: let Sparkle decide devices, shard, and transport.
call sporkle_gemm(ctx, a, b, c, algo="auto", topology="mesh", reduce="none")

! Example: pin to constraints but stay declarative.
call sporkle_gemm(ctx, a, b, c, devices=["cpu","nvidia:0","amd:1"], max_vram_gb=6, prefer_p2p=.true.)
```

* Keyword args everywhere; sane defaults.
* Introspection helpers:

```fortran
call ctx%explain_last_plan()     ! prints device weights, chosen routes
call ctx%trace_begin("train")   ! start span
call ctx%trace_end()
```

---

## 8) Transports & Interop

* **Direct**: CUDA P2P / NVLink, ROCm P2P, Level Zero peer copies.
* **Staged**: pinned host memory + async DMA.
* **Fallback**: shared memory on host; memcpy with NUMA awareness.
* **Optionals**: UCX/MPI backends via thin C shims (kept pluggable to preserve pure-Fortran core).

Interfacing pattern:

```fortran
interface
  function cudaMemcpyPeer(dst, dstDev, src, srcDev, bytes) bind(C, name="cudaMemcpyPeer")
    use iso_c_binding
    type(c_ptr) :: dst, src
    integer(c_int) :: dstDev, srcDev
    integer(c_size_t) :: bytes
    integer(c_int) :: cudaMemcpyPeer
  end function
end interface
```

---

## 9) Failure Handling & Self-Healing

* Heartbeats per device; missed N → mark unhealthy.
* In-flight job retry policy with exponential backoff.
* Recompute plan without the failed node; partial results reconciled via collectives.
* Slow-node detection → reduce shard size or demote to CPU-offload roles.

---

## 10) Minimal Milestone (First Mile)

**M0: CPU-only prototype (2–3 days)**

* `sporkle_gemm` with OpenMP, fake mesh of 1 device.
* Introspection stubs work (prints plan).

**M1: Multi-GPU same vendor (NVIDIA, 3–5 days)**

* Enumerate 2+ CUDA devices; measure H2D/D2H and peer BW.
* Shard GEMM across GPUs with ring all-reduce (sum) for C accumulation.

**M2: Hetero mix (NVIDIA + AMD + CPU) (1 week)**

* HIP + CUDA + OpenMP backends coexisting.
* Cost model chooses shards that keep CPU busy without bottlenecking GPUs.

**M3: Failure experiments (2–3 days)**

* Kill a device mid-run; verify reshard + continue.

---

## 11) Testing & Bench Harness

* Deterministic seeds; golden outputs for small sizes.
* Microbench suite auto-runs on init and caches results.
* Sanity checks: shard boundaries, numerical tolerance, reproducibility flags.

---

## 12) Example: Junk Network Boot

```fortran
program junknet_demo
  use sparkle
  implicit none
  type(sporkle_context) :: ctx
  type(sporkle_array)   :: x, w, y

  ctx = sporkle_init(topology="mesh", profile=.true.)
  call ctx%explain_devices()

  x = ctx%array(shape=[32768, 4096], dtype=real32)
  w = ctx%array(shape=[4096, 4096], dtype=real32)
  y = ctx%array(shape=[32768, 4096], dtype=real32)

  call sporkle_gemm(ctx, x, w, y, algo="auto", reduce="none")
  call ctx%explain_last_plan()
end program
```

---

## 13) Style Guide Nubs (Pythonic Fortran)

* Lowercase module & procedure names, `implicit none` everywhere.
* Descriptive names: `mesh_topology`, `best_route`, `plan_shards`.
* Prefer array expressions; use explicit loops only for perf-critical kernels with comments: `! PERFORMANCE: …`.
* Keyword arguments for public APIs.
* Docstrings as comment blocks above each public procedure explaining **why**.

---

## 14) Open Questions (for Lynn + Claude)

* Do we include UCX/MPI by default or keep pure-Fortran core + optional plugin pack?
* Preferred first collective set: `all_reduce(sum, mean)`, `broadcast`? Others now vs later?
* Any must-have ops beyond GEMM for proving the scheduler (e.g., layernorm, softmax)?

---

## 15) Next Steps

1. Implement `sporkle_types`, `sporkle_discovery` CPU stub.
2. Wire `sporkle_mesh.build_mesh()` + simple `best_route` using host-only routes.
3. Ship `sporkle_gemm` CPU; add introspection.
4. Add CUDA discovery/profiling; enable basic two-GPU sharding.
5. Iterate cost model with real numbers from your lab junk stack.

Let's light up the junk network. ✨