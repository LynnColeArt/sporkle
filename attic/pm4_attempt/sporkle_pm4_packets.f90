module sporkle_pm4_packets
  ! PM4 Packet Generation for AMD GPUs
  ! ===================================
  ! 
  ! PM4 (Packet Manager 4) is AMD's command format for GPU submission.
  ! We build command streams that the GPU's command processor executes.
  
  use kinds
  use iso_c_binding
  implicit none
  private
  
  ! Export packet building functions
  public :: pm4_packet_builder
  public :: pm4_nop, pm4_set_sh_reg, pm4_set_context_reg
  public :: pm4_dispatch_direct, pm4_wait_reg_mem
  public :: pm4_write_data, pm4_acquire_mem
  public :: pm4_build_compute_dispatch
  
  ! PM4 packet types (IT = "Instruction Type")
  integer(i32), parameter :: PACKET_TYPE0 = 0  ! Register writes
  integer(i32), parameter :: PACKET_TYPE1 = 1  ! Deprecated
  integer(i32), parameter :: PACKET_TYPE2 = 2  ! Deprecated  
  integer(i32), parameter :: PACKET_TYPE3 = 3  ! Most commands
  
  ! Common PM4 opcodes
  integer(i32), parameter :: IT_NOP                = int(z'10')
  integer(i32), parameter :: IT_SET_CONTEXT_REG    = int(z'28')
  integer(i32), parameter :: IT_SET_CONFIG_REG     = int(z'2C')
  integer(i32), parameter :: IT_SET_SH_REG         = int(z'2F')
  integer(i32), parameter :: IT_SET_UCONFIG_REG    = int(z'79')
  integer(i32), parameter :: IT_WAIT_REG_MEM       = int(z'46')
  integer(i32), parameter :: IT_WRITE_DATA         = int(z'6A')
  integer(i32), parameter :: IT_ACQUIRE_MEM        = int(z'82')
  integer(i32), parameter :: IT_DISPATCH_DIRECT    = int(z'7D')
  
  ! Register base addresses
  integer(i32), parameter :: SI_CONTEXT_REG_OFFSET = int(z'00028000')
  integer(i32), parameter :: SI_CONFIG_REG_OFFSET  = int(z'00008000')
  integer(i32), parameter :: SI_SH_REG_OFFSET      = int(z'00002C00')
  integer(i32), parameter :: SI_UCONFIG_REG_OFFSET = int(z'00030000')
  
  ! Compute shader registers
  integer(i32), parameter :: COMPUTE_PGM_LO        = int(z'2E12')  ! Lower 32 bits of shader address
  integer(i32), parameter :: COMPUTE_PGM_HI        = int(z'2E13')  ! Upper 32 bits of shader address
  integer(i32), parameter :: COMPUTE_PGM_RSRC1     = int(z'2E14')  ! Resource descriptor 1
  integer(i32), parameter :: COMPUTE_PGM_RSRC2     = int(z'2E15')  ! Resource descriptor 2
  integer(i32), parameter :: COMPUTE_NUM_THREAD_X  = int(z'2E19')  ! Threads per group X
  integer(i32), parameter :: COMPUTE_NUM_THREAD_Y  = int(z'2E1A')  ! Threads per group Y
  integer(i32), parameter :: COMPUTE_NUM_THREAD_Z  = int(z'2E1B')  ! Threads per group Z
  integer(i32), parameter :: COMPUTE_DIM_X         = int(z'2E23')  ! Grid size X
  integer(i32), parameter :: COMPUTE_DIM_Y         = int(z'2E24')  ! Grid size Y
  integer(i32), parameter :: COMPUTE_DIM_Z         = int(z'2E25')  ! Grid size Z
  integer(i32), parameter :: COMPUTE_START_X       = int(z'2E26')  ! Start offset X
  integer(i32), parameter :: COMPUTE_START_Y       = int(z'2E27')  ! Start offset Y
  integer(i32), parameter :: COMPUTE_START_Z       = int(z'2E28')  ! Start offset Z
  integer(i32), parameter :: COMPUTE_USER_DATA_0   = int(z'2E40')  ! User data registers (16 total)
  
  ! PM4 packet builder type
  type :: pm4_packet_builder
    integer(i32), allocatable :: buffer(:)
    integer :: position = 1
    integer :: capacity = 0
  contains
    procedure :: init => pm4_builder_init
    procedure :: ensure_space => pm4_builder_ensure_space
    procedure :: emit => pm4_builder_emit
    procedure :: get_buffer => pm4_builder_get_buffer
    procedure :: get_size => pm4_builder_get_size
    procedure :: cleanup => pm4_builder_cleanup
  end type pm4_packet_builder
  
contains

  ! Initialize packet builder
  subroutine pm4_builder_init(this, initial_capacity)
    class(pm4_packet_builder), intent(inout) :: this
    integer, intent(in), optional :: initial_capacity
    
    integer :: capacity
    
    capacity = 1024  ! Default to 1024 dwords
    if (present(initial_capacity)) capacity = initial_capacity
    
    if (allocated(this%buffer)) deallocate(this%buffer)
    allocate(this%buffer(capacity))
    this%capacity = capacity
    this%position = 1
  end subroutine pm4_builder_init
  
  ! Ensure we have space for N more dwords
  subroutine pm4_builder_ensure_space(this, n)
    class(pm4_packet_builder), intent(inout) :: this
    integer, intent(in) :: n
    
    integer(i32), allocatable :: new_buffer(:)
    integer :: new_capacity
    
    if (this%position + n > this%capacity) then
      new_capacity = max(this%capacity * 2, this%position + n)
      allocate(new_buffer(new_capacity))
      new_buffer(1:this%position-1) = this%buffer(1:this%position-1)
      call move_alloc(new_buffer, this%buffer)
      this%capacity = new_capacity
    end if
  end subroutine pm4_builder_ensure_space
  
  ! Emit a dword to the buffer
  subroutine pm4_builder_emit(this, value)
    class(pm4_packet_builder), intent(inout) :: this
    integer(i32), intent(in) :: value
    
    call this%ensure_space(1)
    this%buffer(this%position) = value
    this%position = this%position + 1
  end subroutine pm4_builder_emit
  
  ! Get buffer contents
  function pm4_builder_get_buffer(this) result(data)
    class(pm4_packet_builder), intent(in) :: this
    integer(i32), allocatable :: data(:)
    
    if (this%position > 1) then
      allocate(data(this%position-1))
      data = this%buffer(1:this%position-1)
    else
      allocate(data(0))
    end if
  end function pm4_builder_get_buffer
  
  function pm4_builder_get_size(this) result(size)
    class(pm4_packet_builder), intent(in) :: this
    integer :: size
    
    size = this%position - 1
  end function pm4_builder_get_size
  
  subroutine pm4_builder_cleanup(this)
    class(pm4_packet_builder), intent(inout) :: this
    
    if (allocated(this%buffer)) deallocate(this%buffer)
    this%position = 1
    this%capacity = 0
  end subroutine pm4_builder_cleanup
  
  ! Build PM4 header for Type 3 packet
  pure function pm4_type3_header(opcode, count) result(header)
    integer(i32), intent(in) :: opcode
    integer, intent(in) :: count  ! Number of DWORDs following header
    integer(i32) :: header
    
    ! Type 3 packet format:
    ! [31:30] = 11b (Type 3)
    ! [29:16] = Count (N-1, where N is number of DWORDs following)
    ! [15:8]  = Opcode
    ! [7:0]   = Reserved/flags
    header = ior(shiftl(3, 30), &                    ! Type 3
                 ior(shiftl(count-1, 16), &          ! Count
                     shiftl(iand(opcode, 255), 8)))  ! Opcode
  end function pm4_type3_header
  
  ! NOP packet (for padding/alignment)
  subroutine pm4_nop(builder, count)
    type(pm4_packet_builder), intent(inout) :: builder
    integer, intent(in), optional :: count
    
    integer :: nop_count, i
    
    nop_count = 1
    if (present(count)) nop_count = max(1, count)
    
    call builder%emit(pm4_type3_header(IT_NOP, nop_count))
    do i = 1, nop_count
      call builder%emit(0)  ! NOP payload
    end do
  end subroutine pm4_nop
  
  ! Set shader register
  subroutine pm4_set_sh_reg(builder, reg_offset, values)
    type(pm4_packet_builder), intent(inout) :: builder
    integer(i32), intent(in) :: reg_offset
    integer(i32), intent(in) :: values(:)
    
    integer :: count, i
    
    count = size(values)
    call builder%emit(pm4_type3_header(IT_SET_SH_REG, count + 1))
    call builder%emit(reg_offset)  ! Register offset from SI_SH_REG_OFFSET
    do i = 1, count
      call builder%emit(values(i))
    end do
  end subroutine pm4_set_sh_reg
  
  ! Set context register
  subroutine pm4_set_context_reg(builder, reg_offset, values)
    type(pm4_packet_builder), intent(inout) :: builder
    integer(i32), intent(in) :: reg_offset
    integer(i32), intent(in) :: values(:)
    
    integer :: count, i
    
    count = size(values)
    call builder%emit(pm4_type3_header(IT_SET_CONTEXT_REG, count + 1))
    call builder%emit(reg_offset)  ! Register offset from SI_CONTEXT_REG_OFFSET
    do i = 1, count
      call builder%emit(values(i))
    end do
  end subroutine pm4_set_context_reg
  
  ! Dispatch compute work
  subroutine pm4_dispatch_direct(builder, dim_x, dim_y, dim_z)
    type(pm4_packet_builder), intent(inout) :: builder
    integer, intent(in) :: dim_x, dim_y, dim_z
    integer(i32) :: dispatch_initiator
    
    ! Build dispatch initiator with required bits
    ! Bit 0: COMPUTE_SHADER_EN = 1 (enable shader execution)
    ! Bit 12: DATA_ATC = 1 (64-bit addressing)
    dispatch_initiator = ior(int(z'00000001', i32), ishft(1_i32, 12))  ! 0x1001
    
    call builder%emit(pm4_type3_header(IT_DISPATCH_DIRECT, 4))  ! 4 dwords!
    call builder%emit(dim_x)  ! Thread groups X
    call builder%emit(dim_y)  ! Thread groups Y
    call builder%emit(dim_z)  ! Thread groups Z
    call builder%emit(dispatch_initiator)  ! COMPUTE_SHADER_EN | DATA_ATC
  end subroutine pm4_dispatch_direct
  
  ! Wait for register to match value
  subroutine pm4_wait_reg_mem(builder, reg_addr, value, mask)
    type(pm4_packet_builder), intent(inout) :: builder
    integer(i64), intent(in) :: reg_addr
    integer(i32), intent(in) :: value, mask
    
    call builder%emit(pm4_type3_header(IT_WAIT_REG_MEM, 5))
    call builder%emit(int(z'00000300'))  ! Wait for register, equal
    call builder%emit(int(reg_addr, int32))  ! Address low
    call builder%emit(int(shiftr(reg_addr, 32), int32))  ! Address high
    call builder%emit(value)  ! Reference value
    call builder%emit(mask)   ! Mask
    call builder%emit(4)      ! Poll interval
  end subroutine pm4_wait_reg_mem
  
  ! Write data to memory
  subroutine pm4_write_data(builder, dst_addr, data)
    type(pm4_packet_builder), intent(inout) :: builder
    integer(i64), intent(in) :: dst_addr
    integer(i32), intent(in) :: data(:)
    
    integer :: count, i
    
    count = size(data)
    call builder%emit(pm4_type3_header(IT_WRITE_DATA, 3 + count))
    call builder%emit(int(z'00000020'))  ! Write to memory
    call builder%emit(int(dst_addr, int32))  ! Address low
    call builder%emit(int(shiftr(dst_addr, 32), int32))  ! Address high
    do i = 1, count
      call builder%emit(data(i))
    end do
  end subroutine pm4_write_data
  
  ! Memory barrier
  subroutine pm4_acquire_mem(builder)
    type(pm4_packet_builder), intent(inout) :: builder
    
    call builder%emit(pm4_type3_header(IT_ACQUIRE_MEM, 5))
    call builder%emit(0)  ! CP_COHER_CNTL
    call builder%emit(0)  ! CP_COHER_SIZE
    call builder%emit(0)  ! CP_COHER_SIZE_HI
    call builder%emit(0)  ! CP_COHER_BASE
    call builder%emit(0)  ! CP_COHER_BASE_HI
    call builder%emit(0)  ! POLL_INTERVAL
  end subroutine pm4_acquire_mem
  
  ! Build complete compute dispatch sequence
  subroutine pm4_build_compute_dispatch(builder, &
                                       shader_addr, &
                                       threads_x, threads_y, threads_z, &
                                       grid_x, grid_y, grid_z, &
                                       user_data)
    type(pm4_packet_builder), intent(inout) :: builder
    integer(i64), intent(in) :: shader_addr
    integer, intent(in) :: threads_x, threads_y, threads_z
    integer, intent(in) :: grid_x, grid_y, grid_z
    integer(i32), intent(in), optional :: user_data(:)
    
    integer(i32) :: pgm_rsrc1, pgm_rsrc2
    integer :: i
    
    ! Build COMPUTE_PGM_RSRC1 register value
    ! This configures the shader execution environment
    pgm_rsrc1 = 0
    pgm_rsrc1 = ior(pgm_rsrc1, shiftl(6, 0))   ! VGPRS = 64 (6 * 4)
    pgm_rsrc1 = ior(pgm_rsrc1, shiftl(2, 6))   ! SGPRS = 32 (2 * 8)
    pgm_rsrc1 = ior(pgm_rsrc1, shiftl(0, 12))  ! PRIORITY = 0
    pgm_rsrc1 = ior(pgm_rsrc1, shiftl(0, 20))  ! FLOAT_MODE = 0
    pgm_rsrc1 = ior(pgm_rsrc1, shiftl(0, 22))  ! PRIV = 0
    pgm_rsrc1 = ior(pgm_rsrc1, shiftl(0, 23))  ! DX10_CLAMP = 0
    pgm_rsrc1 = ior(pgm_rsrc1, shiftl(0, 24))  ! DEBUG_MODE = 0
    pgm_rsrc1 = ior(pgm_rsrc1, shiftl(0, 25))  ! IEEE_MODE = 0
    
    ! Build COMPUTE_PGM_RSRC2 register value
    pgm_rsrc2 = 0
    pgm_rsrc2 = ior(pgm_rsrc2, shiftl(0, 0))   ! SCRATCH_EN = 0
    pgm_rsrc2 = ior(pgm_rsrc2, shiftl(1, 1))   ! USER_SGPR = 2 (s0-s1)
    pgm_rsrc2 = ior(pgm_rsrc2, shiftl(0, 7))   ! TGID_X_EN = 0
    pgm_rsrc2 = ior(pgm_rsrc2, shiftl(0, 8))   ! TGID_Y_EN = 0
    pgm_rsrc2 = ior(pgm_rsrc2, shiftl(0, 9))   ! TGID_Z_EN = 0
    pgm_rsrc2 = ior(pgm_rsrc2, shiftl(0, 10))  ! TG_SIZE_EN = 0
    pgm_rsrc2 = ior(pgm_rsrc2, shiftl(1, 11))  ! TIDIG_COMP_CNT = 1 (X,Y)
    pgm_rsrc2 = ior(pgm_rsrc2, shiftl(0, 13))  ! EXCP_EN_MSB = 0
    pgm_rsrc2 = ior(pgm_rsrc2, shiftl(0, 15))  ! LDS_SIZE = 0
    pgm_rsrc2 = ior(pgm_rsrc2, shiftl(0, 24))  ! EXCP_EN = 0
    
    ! Set shader program address
    call pm4_set_sh_reg(builder, COMPUTE_PGM_LO - SI_SH_REG_OFFSET, &
                       [int(shader_addr, int32), &
                        int(shiftr(shader_addr, 32), int32)])
    
    ! Set shader resources
    call pm4_set_sh_reg(builder, COMPUTE_PGM_RSRC1 - SI_SH_REG_OFFSET, &
                       [pgm_rsrc1, pgm_rsrc2])
    
    ! Set thread group size
    call pm4_set_sh_reg(builder, COMPUTE_NUM_THREAD_X - SI_SH_REG_OFFSET, &
                       [threads_x, threads_y, threads_z])
    
    ! Set user data if provided
    if (present(user_data)) then
      do i = 1, min(size(user_data), 16)
        call pm4_set_sh_reg(builder, &
                           COMPUTE_USER_DATA_0 + i - 1 - SI_SH_REG_OFFSET, &
                           [user_data(i)])
      end do
    end if
    
    ! Set grid dimensions
    call pm4_set_sh_reg(builder, COMPUTE_DIM_X - SI_SH_REG_OFFSET, &
                       [grid_x, grid_y, grid_z])
    
    ! Set start offsets (usually 0)
    call pm4_set_sh_reg(builder, COMPUTE_START_X - SI_SH_REG_OFFSET, &
                       [0, 0, 0])
    
    ! Memory barrier before dispatch
    call pm4_acquire_mem(builder)
    
    ! Dispatch the compute work
    call pm4_dispatch_direct(builder, grid_x, grid_y, grid_z)
    
    ! Memory barrier after dispatch
    call pm4_acquire_mem(builder)
    
  end subroutine pm4_build_compute_dispatch
  
end module sporkle_pm4_packets