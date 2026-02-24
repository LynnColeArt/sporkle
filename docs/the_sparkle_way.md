> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# The Sporkle Way 🌟

## Philosophy

The Sporkle Way is about democratizing compute through radical simplicity and pure Fortran elegance. It's the antithesis of vendor lock-in and complexity bloat.

## Core Principles

### 1. **No External Dependencies**
```fortran
! NOT the Sparkle way:
use cublas
use rocblas  
use mkl

! The Sparkle way:
! Just pure Fortran - the language that's been crunching numbers since 1957
```

### 2. **Talk to the Metal, Not the Middleman**
- Read from `/sys/class/drm/card*/device/` not SDK APIs
- Use kernel drivers, not vendor runtimes
- If it needs an SDK, we probably don't need it

### 3. **Fortran Already Does Math**
```fortran
! NOT the Sparkle way:
call dgemm('N', 'N', m, n, k, alpha, a, lda, b, ldb, beta, c, ldc)

! The Sparkle way:
c = matmul(a, b)  ! Fortran has been doing this for 60 years
```

### 4. **Every Device Matters**
- Your 10-year-old laptop? Welcome to the mesh.
- That Raspberry Pi in the drawer? It's compute now.
- Gaming rig? Obviously.
- "Junk" is just compute that hasn't found its purpose yet.

### 5. **Mesh by Default**
Not client-server. Not master-slave. Just peers, helping each other compute.

### 6. **Pure Procedures, Pure Power**
```fortran
! The Sparkle way - just write Fortran:
subroutine my_kernel(args)
  type(kernel_argument), intent(inout) :: args(:)
  real(real32), pointer :: data(:)
  
  call c_f_pointer(args(1)%data%ptr, data, args(1)%shape)
  
  ! Your computation here - no CUDA, no HIP, just Fortran
  data = sqrt(data) + 1.0
end subroutine
```

### 7. **Transparency Always**
- Build in public
- Fail in public  
- Learn in public
- Bugs are teachers, not embarrassments

### 8. **Strong Types, Clear Intent**
```fortran
! The Sparkle way:
integer(int64) :: bytes_to_allocate
real(real64) :: computation_time
type(device_handle) :: my_gpu

! Not just "integer" or "real" - be explicit!
```

### 9. **Pythonic Thinking, Fortran Execution**
- Clean APIs that feel natural
- Builder patterns where they make sense
- But never at the cost of performance

### 10. **The People's Infrastructure**
This isn't about building the fastest framework. It's about building the most accessible one. Speed comes from scale - a million devices at [deferred throughput metric] beats one device at [deferred throughput metric].

## What The Sporkle Way Is NOT

- ❌ Importing 47 dependencies
- ❌ Requiring specific vendor tools
- ❌ Writing assembly or low-level hacks
- ❌ "Professional" complexity for complexity's sake
- ❌ Closed development behind corporate walls

## In Practice

When faced with a choice, ask:
1. Can pure Fortran do this? (Usually yes)
2. Will this work on someone's old hardware? 
3. Does this add a dependency? (If yes, reconsider)
4. Is this simple enough that a scientist could modify it?
5. Would this make Lynn smile? 

## The Ultimate Test

If a grad student with a 5-year-old laptop can't run your code and contribute compute to the mesh, it's not the Sparkle way.

---

*"Democratize compute. Simplify everything. Trust Fortran."*

That's the Sparkle way. ✨