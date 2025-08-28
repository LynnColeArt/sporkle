! GPU Binary Cache with Compression Support
! =========================================
!
! This module extends gpu_binary_cache with zlib compression to reduce
! disk usage when caching compiled shader binaries.
!
! Features:
! - zlib compression for binary data
! - Automatic fallback if compression fails
! - Compression ratio tracking
! - Backwards compatibility with uncompressed files

module gpu_binary_cache_compressed
  use kinds
  use iso_c_binding
  use gpu_binary_cache
  implicit none
  
  private
  public :: save_program_binary_compressed, load_program_binary_compressed
  public :: compression_init, compression_cleanup
  
  ! Compression header magic number
  integer(i32), parameter :: COMPRESSION_MAGIC = int(z'5A4C4942', i32)  ! 'ZLIB'
  integer(i32), parameter :: COMPRESSION_VERSION = 1
  
  ! zlib constants
  integer(c_int), parameter :: Z_OK = 0
  integer(c_int), parameter :: Z_BEST_COMPRESSION = 9
  integer(c_int), parameter :: Z_DEFAULT_COMPRESSION = 6
  
  ! zlib interfaces
  interface
    ! Compress data
    function compress2(dest, destLen, source, sourceLen, level) &
        bind(C, name="compress2") result(status)
      import :: c_ptr, c_long, c_int
      type(c_ptr), value :: dest, source
      integer(c_long) :: destLen
      integer(c_long), value :: sourceLen
      integer(c_int), value :: level
      integer(c_int) :: status
    end function compress2
    
    ! Uncompress data
    function uncompress(dest, destLen, source, sourceLen) &
        bind(C, name="uncompress") result(status)
      import :: c_ptr, c_long, c_int
      type(c_ptr), value :: dest, source
      integer(c_long) :: destLen
      integer(c_long), value :: sourceLen
      integer(c_int) :: status
    end function uncompress
    
    ! Get compression bound (worst case size)
    function compressBound(sourceLen) bind(C, name="compressBound") result(bound)
      import :: c_long
      integer(c_long), value :: sourceLen
      integer(c_long) :: bound
    end function compressBound
  end interface
  
  ! Module state
  logical, save :: compression_available = .false.
  integer, save :: compression_level = Z_DEFAULT_COMPRESSION
  
contains

  ! Initialize compression system
  subroutine compression_init()
    ! Try to call compressBound to check if zlib is available
    integer(c_long) :: test_bound
    
    ! Test with a small size
    test_bound = compressBound(1000_c_long)
    
    if (test_bound > 0) then
      compression_available = .true.
      print *, "✅ zlib compression available"
    else
      compression_available = .false.
      print *, "⚠️  zlib not available - compression disabled"
    end if
    
  end subroutine compression_init
  
  ! Cleanup compression system
  subroutine compression_cleanup()
    ! Nothing to cleanup for zlib
  end subroutine compression_cleanup
  
  ! Save program binary with compression
  subroutine save_program_binary_compressed(program_id, cache_key, cache_dir)
    integer, intent(in) :: program_id
    character(len=*), intent(in) :: cache_key
    character(len=*), intent(in) :: cache_dir
    
    integer :: binary_length, binary_format
    integer(i8), allocatable, target :: binary_data(:), compressed_data(:)
    type(c_ptr) :: src_ptr, dst_ptr
    character(len=512) :: filepath, gpu_dir
    integer :: unit, iostat
    integer(c_long) :: uncompressed_size, compressed_size, max_compressed_size
    integer(c_int) :: status
    real(dp) :: compression_ratio
    
    ! First, get the uncompressed binary using parent module
    call save_program_binary(program_id, cache_key, cache_dir)
    
    if (.not. compression_available) return
    
    ! Now load it back and compress it
    gpu_dir = trim(cache_dir) // "/" // trim(get_gpu_identifier())
    filepath = trim(gpu_dir) // "/" // trim(cache_key) // ".bin"
    
    ! Read the uncompressed file
    open(newunit=unit, file=filepath, status='old', access='stream', &
         form='unformatted', iostat=iostat)
    if (iostat /= 0) return
    
    ! Read header
    read(unit) binary_format
    read(unit) binary_length
    
    ! Allocate and read binary data
    allocate(binary_data(binary_length))
    read(unit) binary_data
    close(unit)
    
    ! Prepare compression
    uncompressed_size = int(binary_length, c_long)
    max_compressed_size = compressBound(uncompressed_size)
    allocate(compressed_data(max_compressed_size))
    
    src_ptr = c_loc(binary_data)
    dst_ptr = c_loc(compressed_data)
    compressed_size = max_compressed_size
    
    ! Compress the data
    status = compress2(dst_ptr, compressed_size, src_ptr, uncompressed_size, &
                      compression_level)
    
    if (status /= Z_OK) then
      print *, "⚠️  Compression failed, keeping uncompressed file"
      deallocate(binary_data, compressed_data)
      return
    end if
    
    ! Calculate compression ratio
    compression_ratio = real(uncompressed_size, dp) / real(compressed_size, dp)
    
    ! Save compressed file
    filepath = trim(gpu_dir) // "/" // trim(cache_key) // ".binz"
    open(newunit=unit, file=filepath, status='replace', access='stream', &
         form='unformatted', iostat=iostat)
    
    if (iostat == 0) then
      ! Write compressed file header
      write(unit) COMPRESSION_MAGIC
      write(unit) COMPRESSION_VERSION
      write(unit) binary_format
      write(unit) int(uncompressed_size, i32)
      write(unit) int(compressed_size, i32)
      
      ! Write compressed data
      write(unit) compressed_data(1:compressed_size)
      close(unit)
      
      ! Delete uncompressed file
      call execute_command_line("rm -f " // trim(gpu_dir) // "/" // &
                               trim(cache_key) // ".bin", exitstat=iostat)
      
      print '(A,A,A,F4.1,A,I0,A,I0,A)', &
            "🗜️  Compressed ", trim(cache_key), &
            " (", compression_ratio, "x, ", &
            binary_length/1024, " KB → ", &
            compressed_size/1024, " KB)"
    end if
    
    deallocate(binary_data, compressed_data)
    
  end subroutine save_program_binary_compressed
  
  ! Load program binary with decompression
  function load_program_binary_compressed(cache_key, cache_dir) result(program_id)
    character(len=*), intent(in) :: cache_key
    character(len=*), intent(in) :: cache_dir
    integer :: program_id
    
    character(len=512) :: filepath, gpu_dir
    integer :: unit, iostat
    integer :: magic, version, binary_format
    integer(i32) :: uncompressed_size_i32, compressed_size_i32
    integer(c_long) :: uncompressed_size, compressed_size
    integer(i8), allocatable, target :: compressed_data(:), binary_data(:)
    type(c_ptr) :: src_ptr, dst_ptr, binary_ptr
    integer(c_int) :: status
    integer :: link_status
    logical :: file_exists
    
    program_id = 0
    
    ! Check for compressed file first
    gpu_dir = trim(cache_dir) // "/" // trim(get_gpu_identifier())
    filepath = trim(gpu_dir) // "/" // trim(cache_key) // ".binz"
    
    inquire(file=filepath, exist=file_exists)
    if (.not. file_exists) then
      ! Try uncompressed file
      program_id = load_program_binary(cache_key, cache_dir)
      return
    end if
    
    if (.not. compression_available) then
      ! Can't decompress, try uncompressed
      program_id = load_program_binary(cache_key, cache_dir)
      return
    end if
    
    ! Open compressed file
    open(newunit=unit, file=filepath, status='old', access='stream', &
         form='unformatted', iostat=iostat)
    if (iostat /= 0) return
    
    ! Read and verify header
    read(unit, iostat=iostat) magic
    if (iostat /= 0 .or. magic /= COMPRESSION_MAGIC) then
      close(unit)
      ! Try uncompressed file
      program_id = load_program_binary(cache_key, cache_dir)
      return
    end if
    
    read(unit) version
    if (version /= COMPRESSION_VERSION) then
      close(unit)
      print *, "⚠️  Unsupported compression version"
      return
    end if
    
    read(unit) binary_format
    read(unit) uncompressed_size_i32
    read(unit) compressed_size_i32
    
    uncompressed_size = int(uncompressed_size_i32, c_long)
    compressed_size = int(compressed_size_i32, c_long)
    
    ! Allocate buffers
    allocate(compressed_data(compressed_size))
    allocate(binary_data(uncompressed_size))
    
    ! Read compressed data
    read(unit, iostat=iostat) compressed_data
    close(unit)
    
    if (iostat /= 0) then
      deallocate(compressed_data, binary_data)
      return
    end if
    
    ! Decompress
    src_ptr = c_loc(compressed_data)
    dst_ptr = c_loc(binary_data)
    
    status = uncompress(dst_ptr, uncompressed_size, src_ptr, compressed_size)
    
    if (status /= Z_OK) then
      print *, "❌ Decompression failed"
      deallocate(compressed_data, binary_data)
      return
    end if
    
    ! Create program and load binary
    program_id = glCreateProgram()
    if (program_id == 0) then
      deallocate(compressed_data, binary_data)
      return
    end if
    
    binary_ptr = c_loc(binary_data)
    call glProgramBinary(program_id, binary_format, binary_ptr, &
                        int(uncompressed_size, c_int))
    
    ! Link and verify
    call glLinkProgram(program_id)
    call glGetProgramiv(program_id, int(z'8B82', c_int), link_status)
    
    if (link_status == 0) then
      program_id = 0
      print '(A,A)', "⚠️  Binary load failed for: ", trim(cache_key)
    else
      print '(A,A)', "⚡ Loaded compressed binary: ", trim(cache_key)
    end if
    
    deallocate(compressed_data, binary_data)
    
  end function load_program_binary_compressed
  
end module gpu_binary_cache_compressed