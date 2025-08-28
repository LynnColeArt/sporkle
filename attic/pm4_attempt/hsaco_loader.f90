module hsaco_loader
  ! HSACO (HSA Code Object) Loader for PM4
  ! =======================================
  ! Loads compiled RDNA2 kernels from HSACO files
  
  use kinds
  use iso_c_binding
  use elf_parser
  implicit none
  private
  
  public :: hsaco_kernel, load_hsaco_kernel, free_hsaco_kernel
  
  ! ELF and HSACO structures
  integer(i32), parameter :: ELF_MAGIC = int(z'464C457F', i32)  ! 0x7F 'E' 'L' 'F'
  integer(i16), parameter :: ET_DYN = 3_i16  ! Shared object file
  integer(i16), parameter :: EM_AMDGPU = 224_i16  ! AMD GPU
  
  type :: hsaco_kernel
    character(len=256) :: name = ""
    integer(i64) :: code_size = 0
    type(c_ptr) :: code_ptr = c_null_ptr
    integer(i32) :: vgpr_count = 0
    integer(i32) :: sgpr_count = 0
    integer(i32) :: lds_size = 0
    integer(i32) :: scratch_size = 0
    integer(i32) :: rsrc1 = 0
    integer(i32) :: rsrc2 = 0
    integer(i32) :: rsrc3 = 0
  end type hsaco_kernel
  
  ! C library interfaces
  interface
    function c_malloc(size) bind(c, name='malloc')
      import :: c_ptr, c_size_t
      integer(c_size_t), value :: size
      type(c_ptr) :: c_malloc
    end function
    
    subroutine c_free(ptr) bind(c, name='free')
      import :: c_ptr
      type(c_ptr), value :: ptr
    end subroutine
    
    subroutine c_memcpy(dest, src, n) bind(c, name='memcpy')
      import :: c_ptr, c_size_t
      type(c_ptr), value :: dest, src
      integer(c_size_t), value :: n
    end subroutine
  end interface
  
contains

  function load_hsaco_kernel(filename) result(kernel)
    character(len=*), intent(in) :: filename
    type(hsaco_kernel) :: kernel
    
    integer(i8), allocatable, target :: text_data(:)
    integer(i64) :: text_size
    logical :: success
    integer :: i
    
    ! Use ELF parser to extract .text section
    success = parse_elf_text_section(filename, text_data, text_size)
    if (.not. success) then
      print *, "ERROR: Failed to parse ELF file"
      return
    end if
    
    ! For now, use hardcoded values for testing
    ! In production, would parse ELF sections and notes
    print *, "WARNING: Using hardcoded kernel metadata for testing"
    kernel%name = "poke"
    kernel%vgpr_count = 4
    kernel%sgpr_count = 8
    kernel%lds_size = 0
    kernel%scratch_size = 0
    
    ! Compute RSRC values
    call compute_rsrc_values(kernel)
    
    kernel%code_size = text_size
    
    ! Allocate and copy code
    kernel%code_ptr = c_malloc(text_size)
    if (.not. c_associated(kernel%code_ptr)) then
      print *, "ERROR: Failed to allocate memory for kernel code"
      deallocate(text_data)
      return
    end if
    
    ! Copy code section
    call c_memcpy(kernel%code_ptr, c_loc(text_data(1)), text_size)
    
    deallocate(text_data)
    
    print *, "Loaded HSACO kernel:"
    print '(A,A)', "  Name: ", trim(kernel%name)
    print '(A,I0,A)', "  Code size: ", kernel%code_size, " bytes"
    print '(A,I0)', "  VGPRs: ", kernel%vgpr_count
    print '(A,I0)', "  SGPRs: ", kernel%sgpr_count
    print '(A,Z8)', "  RSRC1: 0x", kernel%rsrc1
    print '(A,Z8)', "  RSRC2: 0x", kernel%rsrc2
    
  end function load_hsaco_kernel
  
  subroutine compute_rsrc_values(kernel)
    type(hsaco_kernel), intent(inout) :: kernel
    
    integer :: vgpr_granulated, sgpr_granulated, lds_granulated
    
    ! RSRC1: VGPR and SGPR counts (granulated)
    ! For RDNA2, granulation is different than GCN
    vgpr_granulated = (kernel%vgpr_count + 3) / 4  ! Round up
    sgpr_granulated = (kernel%sgpr_count + 7) / 8  ! Round up
    
    kernel%rsrc1 = ior(iand(vgpr_granulated, z'3F'), &
                       ishft(iand(sgpr_granulated, z'F'), 6))
    
    ! If RSRC1 is 0, use minimal values
    if (kernel%rsrc1 == 0) then
      kernel%rsrc1 = ior(1, ishft(1, 6))  ! 1 VGPR block, 1 SGPR block
    end if
    
    ! RSRC2: Scratch, LDS, and flags
    lds_granulated = kernel%lds_size / 128
    kernel%rsrc2 = int(z'00000092', i32)  ! USER_SGPR + TGID_X
    
    if (kernel%scratch_size > 0) then
      kernel%rsrc2 = ior(kernel%rsrc2, 1)  ! SCRATCH_EN
    end if
    
    kernel%rsrc2 = ior(kernel%rsrc2, ishft(lds_granulated, 8))
    
    ! RSRC3: Usually 0 for simple kernels
    kernel%rsrc3 = 0
    
  end subroutine compute_rsrc_values
  
  subroutine free_hsaco_kernel(kernel)
    type(hsaco_kernel), intent(inout) :: kernel
    
    if (c_associated(kernel%code_ptr)) then
      call c_free(kernel%code_ptr)
      kernel%code_ptr = c_null_ptr
    end if
    
    kernel%code_size = 0
    
  end subroutine free_hsaco_kernel
  
end module hsaco_loader