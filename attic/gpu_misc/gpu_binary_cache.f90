! GPU Binary Cache - Phase 2 Binary Persistence
! =============================================
!
! This module extends gpu_program_cache with binary persistence using
! OpenGL's ARB_get_program_binary extension. Compiled shaders are saved
! to disk and loaded instantly on subsequent runs.
!
! Features:
! - Save/load compiled program binaries
! - GPU model detection for cache invalidation
! - Automatic directory structure management
! - Robust error handling and fallback

module gpu_binary_cache
  use kinds
  use iso_c_binding
  implicit none
  
  private
  public :: save_program_binary, load_program_binary
  public :: get_gpu_identifier, create_cache_directory
  public :: binary_cache_init, binary_cache_cleanup
  
  ! OpenGL constants for program binary
  integer(c_int), parameter :: GL_PROGRAM_BINARY_LENGTH = int(z'8741', c_int)
  integer(c_int), parameter :: GL_NUM_PROGRAM_BINARY_FORMATS = int(z'87FE', c_int)
  integer(c_int), parameter :: GL_PROGRAM_BINARY_FORMATS = int(z'87FF', c_int)
  integer(c_int), parameter :: GL_VENDOR = int(z'1F00', c_int)
  integer(c_int), parameter :: GL_RENDERER = int(z'1F01', c_int)
  integer(c_int), parameter :: GL_VERSION = int(z'1F02', c_int)
  
  ! OpenGL function interfaces for binary operations
  interface
    subroutine glGetProgramiv(program, pname, params) bind(C, name="glGetProgramiv")
      import :: c_int
      integer(c_int), value :: program, pname
      integer(c_int), intent(out) :: params
    end subroutine glGetProgramiv
    
    subroutine glGetProgramBinary(program, bufSize, length, binaryFormat, binary) &
        bind(C, name="glGetProgramBinary")
      import :: c_int, c_ptr
      integer(c_int), value :: program, bufSize
      integer(c_int), intent(out) :: length, binaryFormat
      type(c_ptr), value :: binary
    end subroutine glGetProgramBinary
    
    subroutine glProgramBinary(program, binaryFormat, binary, length) &
        bind(C, name="glProgramBinary")
      import :: c_int, c_ptr
      integer(c_int), value :: program, binaryFormat, length
      type(c_ptr), value :: binary
    end subroutine glProgramBinary
    
    function glGetString(name) bind(C, name="glGetString") result(str_ptr)
      import :: c_int, c_ptr
      integer(c_int), value :: name
      type(c_ptr) :: str_ptr
    end function glGetString
    
    function glGetError() bind(C, name="glGetError") result(error_code)
      import :: c_int
      integer(c_int) :: error_code
    end function glGetError
    
    function glCreateProgram() bind(C, name="glCreateProgram") result(program)
      import :: c_int
      integer(c_int) :: program
    end function glCreateProgram
    
    subroutine glLinkProgram(program) bind(C, name="glLinkProgram")
      import :: c_int
      integer(c_int), value :: program
    end subroutine glLinkProgram
    
    subroutine glGetIntegerv(pname, params) bind(C, name="glGetIntegerv")
      import :: c_int
      integer(c_int), value :: pname
      integer(c_int), intent(out) :: params(*)
    end subroutine glGetIntegerv
  end interface
  
  ! Module variables
  character(len=256), save :: gpu_identifier = ""
  logical, save :: binary_formats_checked = .false.
  integer, save :: num_binary_formats = 0
  integer, allocatable, save :: supported_formats(:)
  
contains

  ! Initialize binary cache system
  subroutine binary_cache_init()
    character(len=256) :: cache_dir
    
    ! Get GPU identifier
    gpu_identifier = get_gpu_identifier()
    
    ! Check supported binary formats
    call check_binary_formats()
    
    if (num_binary_formats == 0) then
      print *, "⚠️  GPU does not support program binaries - falling back to recompilation"
    else
      print '(A,I0,A)', "✅ GPU supports ", num_binary_formats, " binary format(s)"
    end if
    
  end subroutine binary_cache_init
  
  ! Cleanup binary cache
  subroutine binary_cache_cleanup()
    if (allocated(supported_formats)) deallocate(supported_formats)
    binary_formats_checked = .false.
  end subroutine binary_cache_cleanup
  
  ! Check supported binary formats
  subroutine check_binary_formats()
    integer :: i
    integer :: temp(1)
    
    if (binary_formats_checked) return
    
    ! Get number of supported formats
    call glGetIntegerv(GL_NUM_PROGRAM_BINARY_FORMATS, temp)
    num_binary_formats = temp(1)
    
    if (num_binary_formats > 0) then
      allocate(supported_formats(num_binary_formats))
      call glGetIntegerv(GL_PROGRAM_BINARY_FORMATS, supported_formats)
    end if
    
    binary_formats_checked = .true.
  end subroutine check_binary_formats
  
  ! Get unique GPU identifier for cache invalidation
  function get_gpu_identifier() result(identifier)
    character(len=256) :: identifier
    type(c_ptr) :: vendor_ptr, renderer_ptr, version_ptr
    character(len=:), allocatable :: vendor, renderer, version
    
    ! Get GPU strings
    vendor_ptr = glGetString(GL_VENDOR)
    renderer_ptr = glGetString(GL_RENDERER)
    version_ptr = glGetString(GL_VERSION)
    
    ! Convert to Fortran strings
    vendor = c_string_to_fortran(vendor_ptr)
    renderer = c_string_to_fortran(renderer_ptr)
    version = c_string_to_fortran(version_ptr)
    
    ! Create identifier by sanitizing the renderer name
    identifier = sanitize_filename(trim(renderer))
    
    ! Debug output
    if (len_trim(gpu_identifier) == 0) then
      print *, "🎮 GPU Information:"
      print '(A,A)', "   Vendor: ", trim(vendor)
      print '(A,A)', "   Renderer: ", trim(renderer)
      print '(A,A)', "   Version: ", trim(version)
      print '(A,A)', "   Cache ID: ", trim(identifier)
    end if
    
  end function get_gpu_identifier
  
  ! Save program binary to disk
  subroutine save_program_binary(program_id, cache_key, cache_dir)
    integer, intent(in) :: program_id
    character(len=*), intent(in) :: cache_key
    character(len=*), intent(in) :: cache_dir
    
    integer :: binary_length, binary_format
    integer(i8), allocatable, target :: binary_data(:)
    type(c_ptr) :: binary_ptr
    character(len=512) :: filepath, gpu_dir
    integer :: unit, iostat
    logical :: dir_exists
    
    if (num_binary_formats == 0) return  ! No binary support
    
    ! Get binary length
    call glGetProgramiv(program_id, GL_PROGRAM_BINARY_LENGTH, binary_length)
    
    if (binary_length == 0) then
      print *, "⚠️  Program has no binary representation"
      return
    end if
    
    ! Allocate buffer
    allocate(binary_data(binary_length))
    binary_ptr = c_loc(binary_data)
    
    ! Get the binary
    call glGetProgramBinary(program_id, binary_length, binary_length, &
                           binary_format, binary_ptr)
    
    if (glGetError() /= 0) then
      print *, "❌ Failed to get program binary"
      deallocate(binary_data)
      return
    end if
    
    ! Create directory structure: cache_dir/GPU_IDENTIFIER/
    gpu_dir = trim(cache_dir) // "/" // trim(gpu_identifier)
    call create_cache_directory(gpu_dir)
    
    ! Save binary file
    filepath = trim(gpu_dir) // "/" // trim(cache_key) // ".bin"
    open(newunit=unit, file=filepath, status='replace', access='stream', &
         form='unformatted', iostat=iostat)
    
    if (iostat /= 0) then
      print '(A,A)', "❌ Failed to create binary file: ", trim(filepath)
      deallocate(binary_data)
      return
    end if
    
    ! Write header
    write(unit) binary_format
    write(unit) binary_length
    
    ! Write binary data
    write(unit) binary_data
    
    close(unit)
    deallocate(binary_data)
    
    ! Also save metadata
    call save_binary_metadata(cache_key, gpu_dir, binary_format, binary_length)
    
    print '(A,A,A,I0,A)', "💾 Saved binary: ", trim(cache_key), " (", &
                          binary_length/1024, " KB)"
    
  end subroutine save_program_binary
  
  ! Load program binary from disk
  function load_program_binary(cache_key, cache_dir) result(program_id)
    character(len=*), intent(in) :: cache_key
    character(len=*), intent(in) :: cache_dir
    integer :: program_id
    
    character(len=512) :: filepath, gpu_dir
    integer :: unit, iostat
    integer :: binary_format, binary_length, actual_length
    integer(i8), allocatable, target :: binary_data(:)
    type(c_ptr) :: binary_ptr
    integer :: link_status
    logical :: dir_exists
    
    program_id = 0
    
    if (num_binary_formats == 0) return  ! No binary support
    
    ! Check for binary file
    gpu_dir = trim(cache_dir) // "/" // trim(gpu_identifier)
    filepath = trim(gpu_dir) // "/" // trim(cache_key) // ".bin"
    
    ! Check if file exists
    inquire(file=filepath, exist=dir_exists)
    if (.not. dir_exists) return
    
    ! Open and read binary
    open(newunit=unit, file=filepath, status='old', access='stream', &
         form='unformatted', iostat=iostat)
    
    if (iostat /= 0) return
    
    ! Read header
    read(unit, iostat=iostat) binary_format
    if (iostat /= 0) then
      close(unit)
      return
    end if
    
    read(unit, iostat=iostat) binary_length
    if (iostat /= 0) then
      close(unit)
      return
    end if
    
    ! Allocate and read binary data
    allocate(binary_data(binary_length))
    read(unit, iostat=iostat) binary_data
    close(unit)
    
    if (iostat /= 0) then
      deallocate(binary_data)
      return
    end if
    
    ! Create new program and load binary
    program_id = glCreateProgram()
    if (program_id == 0) then
      deallocate(binary_data)
      return
    end if
    
    binary_ptr = c_loc(binary_data)
    call glProgramBinary(program_id, binary_format, binary_ptr, binary_length)
    
    ! Check if load succeeded by trying to link
    call glLinkProgram(program_id)
    call glGetProgramiv(program_id, int(z'8B82', c_int), link_status)  ! GL_LINK_STATUS
    
    if (link_status == 0) then
      ! Binary load failed - cleanup
      ! glDeleteProgram will be called by the cache module
      program_id = 0
      print '(A,A)', "⚠️  Binary load failed for: ", trim(cache_key)
    else
      print '(A,A)', "⚡ Loaded binary: ", trim(cache_key)
    end if
    
    deallocate(binary_data)
    
  end function load_program_binary
  
  ! Save binary metadata
  subroutine save_binary_metadata(cache_key, gpu_dir, format, size)
    character(len=*), intent(in) :: cache_key, gpu_dir
    integer, intent(in) :: format, size
    
    character(len=512) :: filepath
    integer :: unit, iostat
    
    filepath = trim(gpu_dir) // "/" // trim(cache_key) // ".meta"
    open(newunit=unit, file=filepath, status='replace', iostat=iostat)
    
    if (iostat == 0) then
      write(unit, '(A)') "# GPU Program Binary Metadata"
      write(unit, '(A,A)') "cache_key=", trim(cache_key)
      write(unit, '(A,A)') "gpu_id=", trim(gpu_identifier)
      write(unit, '(A,I0)') "format=", format
      write(unit, '(A,I0)') "size=", size
      write(unit, '(A,A)') "timestamp=", get_timestamp()
      close(unit)
    end if
    
  end subroutine save_binary_metadata
  
  ! Create cache directory structure
  subroutine create_cache_directory(dir_path)
    character(len=*), intent(in) :: dir_path
    integer :: stat
    character(len=512) :: command
    
    ! Use system call to create directory (platform-specific)
    ! In production, use proper OS APIs
    command = "mkdir -p " // trim(dir_path)
    call execute_command_line(command, exitstat=stat)
    
    if (stat /= 0) then
      print '(A,A)', "⚠️  Could not create cache directory: ", trim(dir_path)
    end if
    
  end subroutine create_cache_directory
  
  ! Convert C string to Fortran string
  function c_string_to_fortran(c_str_ptr) result(f_str)
    type(c_ptr), intent(in) :: c_str_ptr
    character(len=:), allocatable :: f_str
    character(kind=c_char), pointer :: c_str(:)
    integer :: i, n
    
    if (.not. c_associated(c_str_ptr)) then
      f_str = ""
      return
    end if
    
    ! Find string length
    call c_f_pointer(c_str_ptr, c_str, [1000])  ! Max 1000 chars
    n = 0
    do i = 1, 1000
      if (c_str(i) == c_null_char) exit
      n = n + 1
    end do
    
    ! Copy to Fortran string
    allocate(character(len=n) :: f_str)
    do i = 1, n
      f_str(i:i) = c_str(i)
    end do
    
  end function c_string_to_fortran
  
  ! Sanitize filename for use in paths
  function sanitize_filename(name) result(safe_name)
    character(len=*), intent(in) :: name
    character(len=256) :: safe_name
    integer :: i
    character :: ch
    
    safe_name = ""
    do i = 1, len_trim(name)
      ch = name(i:i)
      ! Replace problematic characters
      select case(ch)
      case(' ', '/', '\', ':', '*', '?', '"', '<', '>', '|', '(', ')')
        safe_name = trim(safe_name) // "_"
      case default
        safe_name = trim(safe_name) // ch
      end select
    end do
    
  end function sanitize_filename
  
  ! Get current timestamp
  function get_timestamp() result(timestamp)
    character(len=32) :: timestamp
    integer :: values(8)
    
    call date_and_time(values=values)
    write(timestamp, '(I4,"-",I2.2,"-",I2.2," ",I2.2,":",I2.2,":",I2.2)') &
          values(1), values(2), values(3), values(5), values(6), values(7)
    
  end function get_timestamp
  
end module gpu_binary_cache