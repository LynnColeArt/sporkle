> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Low-Level AMD Compute Queue Initialization

# (RDNA2)

## MEC Firmware & Compute Queue Setup

On AMD RDNA2 GPUs, the **Micro Engine Compute (MEC)** microcontroller is responsible for managing
compute queues. The AMDGPU kernel driver loads the MEC firmware at device init, so by the time user-
space can submit to a compute queue, the MEC is already running and ready. There are no extra “secret”
registers to manually enable MEC – the driver and firmware handle that. In practice, using the DRM
AMDGPU_HW_IP_COMPUTE interface means the driver has already set up one or more compute rings/
queues for you (with MEC firmware loaded and a scheduler or runlist managing them). So the MEC
initialization sequence (loading firmware, etc.) is done behind the scenes by the driver. Your user-space code
doesn’t need to send special firmware commands; it just needs to ensure you use the provided interfaces
(e.g. creating a context and submitting an IB) so that you’re attaching to a valid compute queue.

**Key point:** As long as you successfully open the render device, create an AMDGPU context, and use a
compute ring index returned by amdgpu_query_hw_ip_info, the MEC should be active. (On a low level,
the **RunList Controller (RLC)** or scheduler firmware assigns a Hardware Queue Descriptor for your
compute queue to the MEC .) There’s no extra “compute mode ON” bit for the MEC itself – if the queue is
set up correctly, the MEC will fetch and execute commands.

## HQD Configuration (Hardware Queue Descriptor)

Each GPU hardware queue (whether graphics or compute) has an HQD – a set of registers that tell the
firmware/CP where the ring buffer is, its size, the doorbell, VMID, etc. In modern AMD GPUs, these HQD
registers are typically managed by firmware (the scheduler) using a **Memory Queue Descriptor (MQD)**.
The MQD is a structure in memory that holds the queue state; loading an MQD “initiates the HQD state”.
In other words, to launch a new compute queue, the firmware copies fields from the MQD into the HQD
registers.

When using the AMDGPU DRM for user-space submission, you usually don’t manually handle HQDs or
MQDs – the driver does it. For example, when you call amdgpu_cs_ctx_create (or the underlying
DRM_IOCTL_AMDGPU_CS with a new context), the driver will allocate an MQD for your queue and either
directly program the HQD via the privileged kernel interface or let the firmware do it (depending on
hardware scheduling mode). In **hardware-scheduler mode** (default on GFX9+), the MEC/RLC firmware
reads the MQD and sets up the HQD automatically. In **legacy mode** (older GPUs or if HWS is disabled), the
driver would use a privileged command (via the KIQ – Kernel Interface Queue) to write HQD registers
directly. On RDNA2 with the standard driver, hardware scheduling is used, so you don’t manually
program HQDs – but you must ensure the queue is properly created so that an MQD is loaded.

```
1
```
```
2
```
```
3
```
```
4
```

**If you suspect the HQD wasn’t set up:** double-check that you created a context and submitted your IB to a
valid compute ring. The amdgpu_cs_submit call should tie your IB to one of the driver’s pre-initialized
compute rings. The driver maintains (for example) up to 8 compute rings that are associated with MEC
pipes; each has a doorbell and an HQD slot reserved. As long as your submission succeeded (fence
returned), the HQD for that ring was _activated_ by the driver. There’s no extra step you need beyond using
the API correctly. In summary, **the HQD is initialized by the driver/firmware** when you create and use a
compute queue (via the context and ring ID). The fact that your fence signaled indicates the CP did process
the IB on that HQD. So the HQD likely _was_ live – the issue lies elsewhere (see below for the dispatch).

## Enabling Compute Dispatch (COMPUTE_DISPATCH_INITIATOR)

One common missing piece for launching waves is setting the **“Compute Shader Enable” bit** in the
dispatch command. On AMD hardware, a PM4 DISPATCH_DIRECT packet includes a dword called
_COMPUTE_DISPATCH_INITIATOR_ , where certain bits control the dispatch behavior. In particular,
**COMPUTE_SHADER_EN must be set to 1** to actually start the compute waves on the CUs. If this bit is 0, the
command processor will parse the dispatch but not launch any wavefronts.

In AMD’s own driver code, you can see how a dispatch packet is constructed: after setting up the registers
for the compute shader, they issue a PACKET3 DISPATCH_DIRECT and supply the workgroup counts (X, Y,
Z) _and_ set COMPUTE_SHADER_EN=1 in the initiator field. For example, a dispatch might look like:

```
Header : DISPATCH_DIRECT (ndw=3)
Payload:
NUM_GROUPS_X (e.g. 16)
NUM_GROUPS_Y (e.g. 1)
NUM_GROUPS_Z (e.g. 1)
DISPATCH_INITIATOR value with COMPUTE_SHADER_EN=
```
In your code snippet from the libdrm test, we see exactly this pattern (16x1x1 groups) and the last dword
0x10 (16 decimal) likely had the enable bit set. In other words, **make sure the final dispatch dword
has the compute shader enable bit = 1**. If you omitted that (or if you wrote a separate
COMPUTE_DISPATCH_INITIATOR register but not tied to the dispatch packet), the CP would not launch
the waves. This is probably the critical fix: incorporate the initiator bit into the DISPATCH packet. The fact
that your fence triggers but no waves execute is a classic symptom of forgetting to set
COMPUTE_SHADER_EN – the IB ends without error, but nothing happens on the CUs.

**Related flags:** The COMPUTE_DISPATCH_INITIATOR has other bits (for example, an optional
ORDERED_APPEND mode for append buffers, and an indicator for using 32-bit pointer mode (DATA_ATC) vs
64-bit). By default, you likely want DATA_ATC = 1 for full 64-bit addressing in flat memory ops (the driver
sets this for compute dispatches). But if you follow the patterns in AMD’s code or the libdrm test, those bits
are likely handled. The main one is COMPUTE_SHADER_EN. (The driver sets it via REG_SET_FIELD(...,
COMPUTE_SHADER_EN, 1) as shown in the snippet .)

### 5 5 • • • • • • 5 6 7


## Preamble and Compute State Setup

It sounds like you have already set up most of the required state, which aligns with AMD’s initialization
sequence. For completeness, here’s the expected preamble for a compute dispatch and how it maps to
what you did:

```
Context Control: On a graphics queue, the driver sends a CONTEXT_CONTROL packet to load
shadow registers (e.g. LOAD_CS_SH_REGS=1) on a context switch. For pure compute queues, this is
often not needed per submission. In the libdrm test, they only issue CONTEXT_CONTROL for GFX
queues, not for compute. Using it with LOAD_CS_SH_REGS=1 on a compute ring shouldn’t
harm, but it’s not strictly necessary each IB. The key is that at least once, the context’s state should
be cleared or initialized. You also issued a CLEAR_STATE which zeros out many registers – that’s
fine as a one-time setup to reset the context.
```
```
Compute Startup Registers: You correctly set COMPUTE_START_X/Y/Z = 0. The AMDGPU test
code explicitly clears those at the start of an IB. These registers are offsets added to the
workgroup ID; they should be 0 for a normal dispatch (you cleared them, or by issuing a
CLEAR_STATE they’d be zero).
```
```
Resource Limits: You set COMPUTE_RESOURCE_LIMITS = 0. The driver does the same (clears it)
as part of the default state. A zero in that register usually means “no special limits, use HW
defaults” which is fine.
```
```
Scratch Ring (TMPRING) Size: You set COMPUTE_TMPRING_SIZE = 0. This tells the GPU no
scratch backing is needed (since your shader likely uses no scratch). The driver also sets this to 0 in
the preamble. If your shader did use scratch and you set 0, that could cause a fault – but
assuming your shader doesn’t use scratch (and clang would have told you if it did), 0 is correct.
```
```
SH_MEM_CONFIG and BASES: You configured SH_MEM_CONFIG and the LDS/GDS bases. This is
important if using 32-bit pointers or specifying how LDS is split. Typically, for modern setups in 64-bit
mode, SH_MEM_CONFIG should have ADDRESS_MODE=1 (64-bit) and set appropriate limits.
The driver’s KFD code notes that for compute dispatches, GPUVM (64-bit) mode is used when
DATA_ATC=1 , which implies SH_MEM_CONFIG.PTR32 is 0 (64-bit pointers). Make sure PTR
bits are 0 so that your dispatch isn’t stuck in a 32-bit addressing mode unexpectedly. (In summary:
ensure 64-bit mode unless you intentionally want 32-bit.)
```
```
Static Thread Mgt (CU Mask): You set all
COMPUTE_STATIC_THREAD_MGMT_SE0-3 = 0xFFFFFFFF. This enables all CUs in all shader arrays
for scheduling. The libdrm code does exactly that, writing 0xFFFFFFFF to each SE’s mask. Good. (If
this were wrong, the waves might be masked off from all CUs – but you set it to all 1s, meaning
“allow any CU”. That’s correct.)
```
```
Shader Program Registers: You loaded your shader code into memory and set COMPUTE_PGM_LO/
HI to the GPU address. The sequence should provide a 48-bit address (on GFX10, bits [47:8] go in
PGM_LO and [47:40] in PGM_HI). The code example shows shifting the address >> 8 for LO
and >> 40 for HI. Double-check your calculations here: an incorrect PGM address would definitely
```
### •

```
8
```
### •

```
9
```
### •

```
10
```
### •

```
11
```
### •

```
6
```
### •

```
12
```
### •

```
13 14
14
```

```
prevent execution. It should point to the start of your compiled shader in GPU VA space , and that
memory must be in the same VM/context as the dispatch. (If you allocated the shader BO and
submitted in the same context, the VA should be correct.)
```
```
PGM_RSRC1 and PGM_RSRC2: You set these according to your shader’s requirements (VGPR count,
SGPR count, etc, plus set WGP_MODE=1). That is correct for RDNA2 if your shader is using Wave
mode (WGP mode groups 2 CUs as a workgroup processor). The values need to match the compiled
code’s registers usage. The libdrm test hardcodes an example: PGM_RSRC1=0x000C0041 and
PGM_RSRC2=0x00000090 for their shader. These likely correspond to VGPR=12 (0xC) and
SGPR=0x41, etc. Ensure your values are right; if PGM_RSRC fields were wrong (e.g. claiming more
registers than available or mismatched SGPR count), the wave could fail to launch. But typically, the
compiler (clang) should have given you the correct values. If uncertain, you might try using Radeon
GPU Analyzer (RGA) or the LLVM AMDGPU disassembler to double-check the register counts in the
code object.
```
```
NUM_THREAD_X/Y/Z: You set the number of threads per workgroup (the local size). The libdrm test,
for example, sets NUM_THREAD_X=0x40 (64), Y=1, Z=1 , meaning each workgroup has 64 threads.
Make sure these match how you intend to launch. If your dispatch is 1 threadgroup of 64 threads,
those should be the values. (It sounds like you did set them appropriately; just be aware these are
per group dimensions, not the grid size.)
```
```
User Data (Compute User SGPRs): In a compute dispatch, user SGPRs (COMPUTE_USER_DATA_n)
are how you pass kernel arguments. The PAL ABI for compute uses user SGPR0/1 typically for a
pointer to a constant/kernel argument buffer. In your case, you wrote COMPUTE_USER_DATA_0/1 –
presumably to pass an address or value to the shader. The libdrm example writes 4 DWORDs to
USER_DATA_0-3 to pass a UAV (destination buffer address, size, and a pattern). Ensure that if
your shader expects certain SGPR inputs, you write them to the matching COMPUTE_USER_DATA
registers before dispatch. (From your description, you did set USER_DATA_0/1 with PAL ABI – so likely
passing a pointer or similar. Just double-check that the shader is actually reading the correct SGPRs
and that they were set in the IB.)
```
After all that state, the **DISPATCH_DIRECT** packet is issued. As noted, the crucial part is the last dword with
COMPUTE_SHADER_EN=1. Additionally, AMD’s driver usually follows the dispatch with a cache flush or wait
packet to ensure completion:

```
Cache Flush / Release: In your IB, you ended with a RELEASE_MEM (EOP event). That’s a valid
way to signal completion – it generates an interrupt/write when all prior work (the dispatch) finishes.
However, if the waves never launched, the EOP would never fire (which matches your observation).
The libdrm test interestingly did not explicitly use RELEASE_MEM; instead it relied on the amdgpu CS
fence mechanism. In the AMD driver code, a common sequence is to insert a CS_PARTIAL_FLUSH or
an EOP event after a dispatch. For example, in an older Carrizo compute example, after each
dispatch they issue: PACKET3(EVENT_WRITE,0); EVENT_TYPE=CS_PARTIAL_FLUSH. This
ensures all waves are done and caches are flushed. In your case, a RELEASE_MEM with an EOP
interrupt is even stronger (full pipeline flush to memory). So using RELEASE_MEM is fine – once the
wave executes.
```
### •

```
15
```
### •

```
16
```
### •

```
17 18
```
### •

```
19
```

In summary, your state setup seems correct and matches known good sequences **except for the dispatch
initiator bit**. The most likely cause of “waves never launch” is that the CP was never told to actually kick off
the compute shader. Make sure the final word of your DISPATCH packet has that bit. Once that is set, the
MEC should schedule the wavefronts on the CUs, your shader code will execute, and the RELEASE_MEM at
end will indeed write the EOP event (allowing the fence to signal from GPU side).

## VMIDs and Buffer Mappings

Each process or context on the GPU is assigned a **VMID** (virtual memory ID) which maps to a page table for
GPU virtual addresses. If your command buffer and shader/data buffers are not in the same GPU VM, the
compute shader won’t see the correct data or code. In practice, if you use the same
amdgpu_device_handle (from amdgpu_device_initialize) and the same context for all allocations
and submissions, you’re fine – everything shares the same GPU VM address space. Problems could arise if,
for example, you allocated memory under one device or DRM file and then submitted commands under a
different one (the VA mappings would differ or the buffers wouldn’t be present).

To ensure VMIDs match: use one device handle for all operations on a given GPU, and use the same context
(or at least the same process). The AMDGPU driver will handle VMID assignment such that all BOs you
allocated are mapped in that context’s page tables, and the IB submission will use that context’s VMID.
Essentially, **the fence you get back is tied to a specific GPU context/VM** – all buffers in the job should
belong to that context. If you accidentally mixed contexts or didn’t properly attach the BOs to the IB (via the
BO list), the GPU could be reading invalid memory. The fact you got a valid fence and no VM fault in dmesg
suggests your VMIDs were probably correct. But double-check that you included _all_ relevant BOs in the
submission’s resource list (shader code BO, any UAV buffer, etc.). The libdrm test, for instance, adds the dest
buffer, shader BO, and IB BO to the bo_list before submission. Missing a BO in the list can lead to invalid
memory access on GPU. In your case, you likely did include them, or you’d have seen a VM page fault. So
VMID mismatch is less likely the culprit here.

## Doorbell Considerations

AMD GPUs use **doorbells** (memory-mapped IO registers) to notify the CP of new work on a queue. When
you submit an IB on a compute ring, the driver will update the ring’s write pointer and ring the doorbell so
the MEC knows there is new work. With the amdgpu DRM, this is handled internally: you don’t manually ring
doorbells when using amdgpu_cs_submit. The driver knows the doorbell index for the chosen compute
ring and writes it as needed. (Each compute ring has a doorbell offset assigned – e.g. doorbell for Compute
Ring 0, etc. These were set up when the driver initialized the rings.)

So normally, you **do not need any special doorbell setup** in user-space beyond what the ioctl does. If the
fence signaled, it means the doorbell _was_ rung and the IB was processed. In a DIY scenario (like using KFD’s
user-mode queue interfaces), you might map doorbells and poke them yourself. But here, since you rely on
DRM_IOCTL_AMDGPU_CS, doorbells are automatic. There’s no separate “compute doorbell enable” you
must do. The only caveat: ensure you don’t override the doorbell in your packets. (For example, certain
PACKET3 can write to registers – but you didn’t mention doing that.) In short, the doorbell is not likely your
issue, as the command processor clearly fetched and executed your PM4 up to a point (again, the fence
came back).

```
20
```

## MQD Structure – Do You Need to Set One Up?

If you were writing a driver or using the ROCm KFD interface, you’d allocate and initialize an MQD for your
queue (filling in things like base address, size, doorbell, priority, etc.), then call an ioctl to create a queue
which loads that MQD into an HQD. **However, when using the AMDGPU graphics/compute interface,
you do not manually handle the MQD.** The driver either uses a static pre-initialized MQD (for the fixed
number of compute queues) or it initializes one on the fly when you create a context. The details are largely
hidden. For instance, on older GPUs without the new MES scheduler, AMDGPU had a fixed number of
compute queues set up at driver load (say 8 compute HQDs in MEC0 Pipe 0-1 etc.). These have
corresponding MQDs that the driver manages. When you submit to “ring 0” of the compute engine, you’re
using the first of those queues. In newer developments (RDNA3 with MES), user-space can create queues
more dynamically, but on RDNA2 it’s mostly static.

So, **you do not need to allocate or program an MQD in your user code** – the kernel has done it. In fact,
touching MQD/HQD directly is only possible from privileged context (the driver or PSP firmware). As
evidence, the amdgpu driver’s KFD layer has code for managing MQDs but that’s only used when you go
through the ROCm path; normal graphics/compute submissions don’t expose that to you. The MQD simply
needs to reflect correct info – and if something were wrong there (say a wrong VMID or base pointer), your
queue wouldn’t run at all. Given that the IB was read, the MQD/HQD was likely fine.

To summarize the MQD/HQD topic: **the final transformation from a “ring exists” to “waves execute” is
the dispatch command itself.** Once the HQD is active and your IB is being read, the only thing left is
ensuring the PM4 tells the CUs to run the shader. That happens via the DISPATCH packet and its initiator
bits. If those bits are set and all state is valid, the waves _will_ launch on the next cycle.

## Putting It All Together – Missing Piece Identified

Based on all the above, the most probable missing piece in your sequence is the
**COMPUTE_DISPATCH_INITIATOR (COMPUTE_SHADER_EN) bit in the dispatch command**. All other
infrastructure – MEC firmware, HQD/MQD setup, doorbells, VMIDs – should be handled by the driver as
long as you use the API correctly. Indeed, AMD’s own documentation/code confirms that to launch a
compute dispatch, you must “poke” the compute dispatch initiator properly. In an X post directed at
AMD, developers hinted that they were “bypassing most of the MEC” and just needed to know what
happens after poking COMPUTE_DISPATCH_INITIATOR – which implies that setting up all the state and
then triggering the dispatch is the key moment.

**Action Items / Checklist:**

```
Set COMPUTE_SHADER_EN=1 in DISPATCH_DIRECT: Incorporate this into your PM4 stream (it can
be done by making the last dword of the DISPATCH_DIRECT packet have bit 0 (maybe bit 31
depending on how it’s defined) set to 1). For GFX10, the AMD macro was REG_SET_FIELD(0,
COMPUTE_DISPATCH_INITIATOR, COMPUTE_SHADER_EN, 1) which sets the appropriate bit.
The rest of that field can likely be 0 for your purposes (it’s typically just bitfields).
```
```
Double-check all register writes: Ensure your IB exactly matches the sequence of a known-good
example. The Mesa/RADV or AMD code sequence is:
```
```
21 5
```
```
22
```
### 1.

```
7
```
### 2.


```
(If GFX ring: CONTEXT_CONTROL – not needed for compute ring)
Write default compute state (start regs =0, resource_limits=0, etc.)
Set CU mask registers to 0xFFFFFFFF
Set up shader: PGM_LO/HI, PGM_RSRCs, NUM_THREAD_X/Y/Z
Set up any user data SGPRs (addresses or constants)
Issue DISPATCH_DIRECT with correct XYZ and initiator
(Optionally, issue an EVENT_WRITE for CS_PARTIAL_FLUSH or a RELEASE_MEM for EOP to signal
completion)
```
Compare this with your PM4 packet list – it appears you did all of these except perhaps the initiator bit. One
nuance: the **ordering** of packets can matter. The CLEAR_STATE at the very top is okay to reset state, but
typically the sequence above (setting regs and dispatch) should be in one IB that executes atomically. Make
sure no other packets (like an EOP release) come _before_ the dispatch – the release_mem should be the last
thing after the dispatch, otherwise you’d signal completion too early.

```
Test on the simpler hardware (Raphael iGPU): Since it’s only 2 CUs, you can try a very small
dispatch (1 workgroup of 1 wave) with a simple shader (e.g. one that writes a known constant to a
buffer and triggers an S_SLEEP for a short loop). With COMPUTE_SHADER_EN set, you should see the
buffer get written. Use the Linux dmesg to catch any GPU faults – if something is still wrong (like
VM fault or invalid register programming), the driver will usually log it.
```
```
No Manual MQD/MQD needed: You don’t need to manually construct MQDs or doorbells. Continue
to rely on amdgpu_cs_submit and associated calls, as they abstract that. If you ever venture into
the ROCm KFD interface (which provides KFD_IOC_CREATE_QUEUE etc.), then you’d deal with
queue properties (including an MQD that the kernel fills in). But since you’re bypassing ROCm and
using the DRM interface, stick with that approach.
```
In conclusion, transforming a “ring that accepts commands” into “waves that execute” boils down to
sending the proper PM4 dispatch sequence. The **final trigger is the COMPUTE_DISPATCH_INITIATOR field**
in the dispatch packet. After correcting that, your compute shader should run to completion on the CUs
(verify by memory side-effects or using a GPU debugger/profiler if available). This aligns with both AMD’s
official drivers and reverse-engineered examples, which all ensure that bit is set before expecting any waves
to launch. Good luck, and happy computing on bare-metal AMD GPUs!

**Sources:**

```
AMD driver documentation and code examples for setting up compute dispatch
AMDGPU Kernel Developer Guide – MEC, HQD/MQD definitions
AMDGPU libdrm test for compute IB dispatch (illustrates required PM4 packets)
Discussions of COMPUTE_DISPATCH_INITIATOR usage in AMD GPU context
```
drm/amdgpu - Graphics and Compute (GC) — The Linux Kernel documentation
https://docs.kernel.org/gpu/amdgpu/gc/index.html

Linux v6.6.1 - drivers/gpu/drm/amd/amdkfd/kfd_mqd_manager.h
https://sbexr.rabexc.org/latest/sources/d7/7e5829342c7e4f.html

### 3.^8

### 4.^9

### 5.^12

### 6.^1323

### 7.

### 8.^5

### 9.

```
19
```
### 1.

### 2.

```
5
```
### •^9125

### •^13

### •^912135

### •^216

```
1 2
```
```
3 4
```

drivers/gpu/drm/amd/amdgpu/gfx_v8_0.c - linux-imx - Git at Google
https://coral.googlesource.com/linux-imx/+/refs/tags/4-2/drivers/gpu/drm/amd/amdgpu/gfx_v8_0.c?
autodive=[deferred percent]2F%2F%2F%2F%2F%2F%2F%2F%2F%2F%2F%2F%2F%2F%2F

git.apps.os.sepia.ceph.com Git - git.apps.os.sepia.ceph.com Git - Ceph
https://git.ceph.com/?p=ceph-client.git;a=blob;f=drivers/gpu/drm/amd/amdkfd/
kfd_flat_memory.c;h=e64aa99e5e416349071f3c0906be347ed42e3e53;hb=0ad4989d6270bec0a42598dd4d804569faedf

[PATCH libdrm 1/4] tests/amdgpu: add memset dispatch test
https://www.mail-archive.com/amd-gfx@lists.freedesktop.org/msg31383.html

the tiny corp on X: ".@AMD @amdradeon released some MES ...
https://twitter.com/__tinygrad__/status/

drivers/gpu/drm/amd/amdkfd/kfd_flat_memory.c - linux-imx
https://coral.googlesource.com/linux-imx/+/refs/tags/4-2/drivers/gpu/drm/amd/amdkfd/kfd_flat_memory.c

```
5 7 19
```
```
6
```
```
8 9 10 11 12 13 14 15 16 17 18 20 23
```
```
21
```
```
22
```

