module pm4_conv2d_builder
  ! PM4 Conv2D Command Builder
  ! ==========================
  !
  ! Builds PM4 command sequences for Conv2D operations
  ! This is the Neo Geo style direct programming interface
  
  use kinds
  use iso_c_binding
  use sporkle_pm4_packets
  use gpu_ring_buffer
  implicit none
  
  ! PM4 opcodes (from sporkle_pm4_packets)
  integer(i32), parameter :: IT_SET_SH_REG = int(z'2F', i32)
  integer(i32), parameter :: IT_DISPATCH_DIRECT = int(z'7D', i32)
  integer(i32), parameter :: IT_ACQUIRE_MEM = int(z'82', i32)
  
  ! Register offsets
  integer(i32), parameter :: SI_SH_REG_OFFSET = int(z'00002C00', i32)
  
  ! Compute shader registers
  integer(i32), parameter :: COMPUTE_NUM_THREAD_X = int(z'2E19', i32)
  integer(i32), parameter :: COMPUTE_NUM_THREAD_Y = int(z'2E1A', i32)
  integer(i32), parameter :: COMPUTE_NUM_THREAD_Z = int(z'2E1B', i32)
  integer(i32), parameter :: COMPUTE_START_X = int(z'2E26', i32)
  integer(i32), parameter :: COMPUTE_START_Y = int(z'2E27', i32)
  integer(i32), parameter :: COMPUTE_START_Z = int(z'2E28', i32)
  integer(i32), parameter :: COMPUTE_PGM_LO = int(z'2E12', i32)
  integer(i32), parameter :: COMPUTE_PGM_HI = int(z'2E13', i32)
  integer(i32), parameter :: COMPUTE_PGM_RSRC1 = int(z'2E14', i32)
  integer(i32), parameter :: COMPUTE_PGM_RSRC2 = int(z'2E15', i32)
  
  private
  public :: pm4_build_conv2d_dispatch
  public :: pm4_build_buffer_setup
  public :: pm4_build_shader_setup
  public :: pm4_conv2d_params
  
  ! Conv2D parameters for PM4
  type :: pm4_conv2d_params
    ! Buffer addresses
    integer(i64) :: input_addr
    integer(i64) :: weight_addr
    integer(i64) :: output_addr
    integer(i64) :: param_addr
    
    ! Dimensions
    integer :: n, c, h, w, k
    integer :: kernel_size, stride, pad
    integer :: h_out, w_out
    
    ! Dispatch dimensions
    integer :: workgroups_x
    integer :: workgroups_y 
    integer :: workgroups_z
    
    ! Shader info
    integer(i64) :: shader_addr
    integer :: num_vgprs
    integer :: num_sgprs
  end type
  
  ! RDNA3 compute shader registers
  integer, parameter :: COMPUTE_DIM_X = int(z'2C09')
  integer, parameter :: COMPUTE_DIM_Y = int(z'2C0A')
  integer, parameter :: COMPUTE_DIM_Z = int(z'2C0B')
  
  ! Buffer descriptor registers (user data)
  integer, parameter :: COMPUTE_USER_DATA_0 = int(z'2C40')
  
contains

  ! Build complete Conv2D dispatch sequence
  subroutine pm4_build_conv2d_dispatch(ring, params)
    type(ring_buffer), intent(inout) :: ring
    type(pm4_conv2d_params), intent(in) :: params
    
    ! 1. Set up shader
    call pm4_build_shader_setup(ring, params)
    
    ! 2. Set up buffers
    call pm4_build_buffer_setup(ring, params)
    
    ! 3. Set dispatch dimensions
    call pm4_build_dispatch_dims(ring, params)
    
    ! 4. Issue dispatch
    call pm4_build_dispatch_packet(ring)
    
    ! 5. Insert fence for completion
    call pm4_build_fence_release(ring)
    
  end subroutine pm4_build_conv2d_dispatch
  
  ! Set up compute shader
  subroutine pm4_build_shader_setup(ring, params)
    type(ring_buffer), intent(inout) :: ring
    type(pm4_conv2d_params), intent(in) :: params
    
    integer(i32) :: dwords(16)
    integer :: pgm_rsrc1, pgm_rsrc2
    
    ! Build COMPUTE_PGM_RSRC1
    ! [5:0] = VGPRS (in units of 4)
    ! [9:6] = SGPRS (in units of 8) 
    ! [11:10] = Priority
    ! [13:12] = Float mode
    ! [15:14] = PRIV
    ! [18] = DX10_CLAMP
    ! [19] = DEBUG_MODE
    ! [20] = IEEE_MODE
    pgm_rsrc1 = ior(params%num_vgprs / 4, ishft(params%num_sgprs / 8, 6))
    pgm_rsrc1 = ior(pgm_rsrc1, ishft(1, 18))  ! DX10_CLAMP
    pgm_rsrc1 = ior(pgm_rsrc1, ishft(1, 20))  ! IEEE_MODE
    
    ! Build COMPUTE_PGM_RSRC2
    ! [5:0] = SCRATCH_EN
    ! [6] = USER_SGPR
    ! [7] = TRAP_PRESENT
    ! [8] = TGID_X_EN
    ! [9] = TGID_Y_EN 
    ! [10] = TGID_Z_EN
    ! [11] = TG_SIZE_EN
    ! [24:23] = EXCP_EN
    pgm_rsrc2 = ior(1, ishft(1, 6))   ! USER_SGPR
    pgm_rsrc2 = ior(pgm_rsrc2, ishft(1, 8))   ! TGID_X_EN
    pgm_rsrc2 = ior(pgm_rsrc2, ishft(1, 9))   ! TGID_Y_EN
    pgm_rsrc2 = ior(pgm_rsrc2, ishft(1, 10))  ! TGID_Z_EN
    
    ! Write shader address
    call ring_buffer_write_packet(ring, IT_SET_SH_REG, 2)
    dwords(1) = COMPUTE_PGM_LO
    dwords(2) = int(params%shader_addr, i32)
    dwords(3) = int(ishft(params%shader_addr, -32), i32)
    call ring_buffer_write_dwords(ring, dwords, 3)
    
    ! Write shader resources
    call ring_buffer_write_packet(ring, IT_SET_SH_REG, 2)
    dwords(1) = COMPUTE_PGM_RSRC1
    dwords(2) = pgm_rsrc1
    dwords(3) = pgm_rsrc2
    call ring_buffer_write_dwords(ring, dwords, 3)
    
    ! Set thread group size (hardcoded 256 threads = 16x16x1)
    call ring_buffer_write_packet(ring, IT_SET_SH_REG, 3)
    dwords(1) = COMPUTE_NUM_THREAD_X
    dwords(2) = 16   ! X threads
    dwords(3) = 16   ! Y threads  
    dwords(4) = 1    ! Z threads
    call ring_buffer_write_dwords(ring, dwords, 4)
    
  end subroutine pm4_build_shader_setup
  
  ! Set up buffer descriptors
  subroutine pm4_build_buffer_setup(ring, params)
    type(ring_buffer), intent(inout) :: ring
    type(pm4_conv2d_params), intent(in) :: params
    
    integer(i32) :: dwords(32)
    integer :: i, reg_offset
    
    ! Each buffer descriptor is 4 dwords:
    ! DW0: Base address low
    ! DW1: Base address high | stride
    ! DW2: Num records
    ! DW3: Dst_sel | Num_format | Data_format | Flags
    
    reg_offset = 0
    
    ! Input buffer descriptor (USER_DATA_0)
    call pm4_build_buffer_descriptor(dwords(1:4), params%input_addr, &
                                   int(params%n * params%c * params%h * params%w * 4, i64))
    
    ! Weight buffer descriptor (USER_DATA_4)
    call pm4_build_buffer_descriptor(dwords(5:8), params%weight_addr, &
                                   int(params%k * params%c * params%kernel_size * params%kernel_size * 4, i64))
    
    ! Output buffer descriptor (USER_DATA_8)
    call pm4_build_buffer_descriptor(dwords(9:12), params%output_addr, &
                                   int(params%n * params%k * params%h_out * params%w_out * 4, i64))
    
    ! Param buffer descriptor (USER_DATA_12)
    call pm4_build_buffer_descriptor(dwords(13:16), params%param_addr, 40_i64)  ! 10 ints
    
    ! Write all buffer descriptors
    call ring_buffer_write_packet(ring, IT_SET_SH_REG, 16)
    dwords(17) = COMPUTE_USER_DATA_0
    call ring_buffer_write_dwords(ring, dwords(17:17), 1)
    call ring_buffer_write_dwords(ring, dwords(1:16), 16)
    
  end subroutine pm4_build_buffer_setup
  
  ! Build buffer descriptor
  subroutine pm4_build_buffer_descriptor(desc, base_addr, size_bytes)
    integer(i32), intent(out) :: desc(4)
    integer(i64), intent(in) :: base_addr
    integer(i64), intent(in) :: size_bytes
    
    ! DW0: Base address low
    desc(1) = int(base_addr, i32)
    
    ! DW1: Base address high (48-bit address)
    desc(2) = int(ishft(base_addr, -32), i32)
    
    ! DW2: Size in bytes - 1
    desc(3) = int(size_bytes - 1, i32)
    
    ! DW3: Resource flags
    ! [2:0] = DST_SEL_X/Y/Z/W (XYZW = 0x0)
    ! [6:3] = NUM_FORMAT (FLOAT = 0x7)
    ! [10:7] = DATA_FORMAT (32_32_32_32 = 0x0C for simplicity)
    ! [12] = ADD_TID_ENABLE
    desc(4) = ior(ishft(7, 3), ishft(12, 7))  ! FLOAT, 32-bit format
    
  end subroutine pm4_build_buffer_descriptor
  
  ! Set dispatch dimensions
  subroutine pm4_build_dispatch_dims(ring, params)
    type(ring_buffer), intent(inout) :: ring
    type(pm4_conv2d_params), intent(in) :: params
    
    integer(i32) :: dwords(8)
    
    ! Set grid dimensions
    call ring_buffer_write_packet(ring, IT_SET_SH_REG, 3)
    dwords(1) = COMPUTE_DIM_X
    dwords(2) = params%workgroups_x
    dwords(3) = params%workgroups_y
    dwords(4) = params%workgroups_z
    call ring_buffer_write_dwords(ring, dwords, 4)
    
    ! Set start position (all zeros)
    call ring_buffer_write_packet(ring, IT_SET_SH_REG, 3)
    dwords(1) = COMPUTE_START_X
    dwords(2) = 0
    dwords(3) = 0
    dwords(4) = 0
    call ring_buffer_write_dwords(ring, dwords, 4)
    
  end subroutine pm4_build_dispatch_dims
  
  ! Issue dispatch packet
  subroutine pm4_build_dispatch_packet(ring)
    type(ring_buffer), intent(inout) :: ring
    
    integer(i32) :: dwords(4)
    
    ! DISPATCH_DIRECT packet
    ! DW0: Header (set by write_packet)
    ! DW1: DIM_X
    ! DW2: DIM_Y  
    ! DW3: DIM_Z
    ! DW4: DISPATCH_INITIATOR
    
    call ring_buffer_write_packet(ring, IT_DISPATCH_DIRECT, 4)
    
    ! Dimensions are already set via SET_SH_REG
    dwords(1) = 1  ! X dimension
    dwords(2) = 1  ! Y dimension
    dwords(3) = 1  ! Z dimension
    
    ! DISPATCH_INITIATOR
    ! [0] = COMPUTE_SHADER_EN
    ! [1] = PARTIAL_TG_EN
    ! [2] = FORCE_START_AT_000
    ! [3] = ORDERED_APPEND_ENBL
    dwords(4) = 1  ! COMPUTE_SHADER_EN
    
    call ring_buffer_write_dwords(ring, dwords, 4)
    
  end subroutine pm4_build_dispatch_packet
  
  ! Build fence release
  subroutine pm4_build_fence_release(ring)
    type(ring_buffer), intent(inout) :: ring
    
    integer(i32) :: dwords(8)
    
    ! RELEASE_MEM packet for fence
    call ring_buffer_write_packet(ring, IT_ACQUIRE_MEM, 6)  ! Use ACQUIRE_MEM for sync
    
    ! DW1: EVENT_TYPE | EVENT_INDEX
    dwords(1) = ior(ishft(15, 0), ishft(5, 8))  ! CS_DONE, EVENT_INDEX=5
    
    ! DW2: DATA_SEL | INT_SEL
    dwords(2) = ior(ishft(0, 29), ishft(0, 24))  ! Write data
    
    ! DW3: Address low
    dwords(3) = 0  ! Will be patched later
    
    ! DW4: Address high
    dwords(4) = 0  ! Will be patched later
    
    ! DW5: Data low
    dwords(5) = 1  ! Fence value
    
    ! DW6: Data high
    dwords(6) = 0
    
    call ring_buffer_write_dwords(ring, dwords, 6)
    
  end subroutine pm4_build_fence_release
  
end module pm4_conv2d_builder