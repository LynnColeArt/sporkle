! GPU Program Cache - Persistent Kernel Framework
! ===============================================
!
! Keeps compiled GPU programs in memory to eliminate recompilation overhead.
! Features:
! - Reference counting for safe lifecycle management
! - LRU eviction when cache is full
! - Binary caching to disk (Phase 2)
! - Integration with async executor
!
! Part of the Sporkle persistent kernel framework - compile once, run forever!

module gpu_program_cache
  use kinds
  use iso_c_binding
  implicit none
  
  private
  public :: program_cache, program_cache_entry
  public :: init_program_cache, cleanup_program_cache
  public :: get_cached_program, release_program
  public :: cache_program, find_program, evict_lru
  public :: print_cache_stats, get_cache_stats
  
  ! Individual cache entry
  type :: program_cache_entry
    integer :: program_id = 0          ! OpenGL program object
    character(len=256) :: key = ""     ! Unique identifier
    integer :: ref_count = 0           ! Active references
    integer(i64) :: last_used = 0    ! Timestamp for LRU
    integer(i64) :: compile_time = 0 ! Microseconds to compile
    real(sp) :: performance = 0.0  ! Measured GFLOPS
    logical :: is_binary_cached = .false. ! Saved to disk?
    integer(i64) :: memory_size = 0  ! Estimated GPU memory usage
  end type program_cache_entry
  
  ! Main cache structure
  type :: program_cache
    type(program_cache_entry), allocatable :: entries(:)
    integer :: num_entries = 0
    integer :: max_entries = 100
    character(len=256) :: cache_dir = "shader_cache/"
    logical :: auto_save = .true.
    logical :: initialized = .false.
    
    ! Statistics
    integer(i64) :: total_compilations = 0
    integer(i64) :: cache_hits = 0
    integer(i64) :: cache_misses = 0
    integer(i64) :: total_compile_time = 0
    integer(i64) :: memory_saved = 0
  end type program_cache
  
  ! OpenGL function interfaces
  interface
    subroutine glDeleteProgram(program) bind(C, name="glDeleteProgram")
      import :: c_int
      integer(c_int), value :: program
    end subroutine glDeleteProgram
    
    function glIsProgram(program) bind(C, name="glIsProgram") result(is_program)
      import :: c_int
      integer(c_int), value :: program
      integer(c_int) :: is_program
    end function glIsProgram
  end interface
  
contains

  ! Initialize the program cache
  subroutine init_program_cache(cache, max_programs, cache_directory)
    type(program_cache), intent(out) :: cache
    integer, intent(in), optional :: max_programs
    character(len=*), intent(in), optional :: cache_directory
    
    ! Set parameters
    if (present(max_programs)) then
      cache%max_entries = max_programs
    else
      cache%max_entries = 100  ! Default
    end if
    
    if (present(cache_directory)) then
      cache%cache_dir = trim(cache_directory)
    else
      cache%cache_dir = "shader_cache/"
    end if
    
    ! Allocate entry array
    allocate(cache%entries(cache%max_entries))
    cache%num_entries = 0
    
    ! Initialize statistics
    cache%total_compilations = 0
    cache%cache_hits = 0
    cache%cache_misses = 0
    cache%total_compile_time = 0
    cache%memory_saved = 0
    
    cache%initialized = .true.
    
    print *, "🚀 GPU Program Cache initialized"
    print '(A,I0,A)', "   Max programs: ", cache%max_entries
    print '(A,A)', "   Cache directory: ", trim(cache%cache_dir)
    
  end subroutine init_program_cache
  
  ! Get a cached program or compile new one
  function get_cached_program(cache, shader_source, cache_key, compile_func) result(program_id)
    type(program_cache), intent(inout) :: cache
    character(len=*), intent(in) :: shader_source
    character(len=*), intent(in) :: cache_key
    interface
      function compile_func(source) result(prog_id)
        character(len=*), intent(in) :: source
        integer :: prog_id
      end function compile_func
    end interface
    integer :: program_id
    
    integer :: idx
    integer(i64) :: start_time, end_time, compile_time
    real(dp) :: clock_rate
    
    if (.not. cache%initialized) then
      print *, "ERROR: Program cache not initialized!"
      program_id = 0
      return
    end if
    
    ! Check if program exists in cache
    idx = find_program(cache, cache_key)
    
    if (idx > 0) then
      ! Cache hit!
      cache%cache_hits = cache%cache_hits + 1
      cache%entries(idx)%ref_count = cache%entries(idx)%ref_count + 1
      call system_clock(cache%entries(idx)%last_used)
      program_id = cache%entries(idx)%program_id
      
      if (cache%cache_hits < 10 .or. mod(cache%cache_hits, 100) == 0) then
        print '(A,A,A,I0)', "✅ Cache hit: ", trim(cache_key), " (refs: ", cache%entries(idx)%ref_count, ")"
      end if
      
    else
      ! Cache miss - need to compile
      cache%cache_misses = cache%cache_misses + 1
      
      print '(A,A)', "🔄 Compiling shader: ", trim(cache_key)
      
      ! Time the compilation
      call system_clock(start_time, count_rate=clock_rate)
      program_id = compile_func(shader_source)
      call system_clock(end_time)
      
      compile_time = (end_time - start_time) * 1000000 / int(clock_rate, int64)  ! microseconds
      
      if (program_id > 0) then
        ! Add to cache
        call cache_program(cache, program_id, cache_key, compile_time)
        cache%total_compilations = cache%total_compilations + 1
        cache%total_compile_time = cache%total_compile_time + compile_time
        
        print '(A,F6.2,A)', "   Compilation took ", real(compile_time) / 1000.0, " ms"
      else
        print *, "❌ Shader compilation failed!"
      end if
    end if
    
  end function get_cached_program
  
  ! Add program to cache
  subroutine cache_program(cache, program_id, cache_key, compile_time)
    type(program_cache), intent(inout) :: cache
    integer, intent(in) :: program_id
    character(len=*), intent(in) :: cache_key
    integer(i64), intent(in) :: compile_time
    
    integer :: idx
    
    ! Check if we need to evict
    if (cache%num_entries >= cache%max_entries) then
      call evict_lru(cache)
    end if
    
    ! Find empty slot
    idx = cache%num_entries + 1
    if (idx > cache%max_entries) then
      print *, "WARNING: Cache full after eviction!"
      return
    end if
    
    ! Add new entry
    cache%entries(idx)%program_id = program_id
    cache%entries(idx)%key = cache_key
    cache%entries(idx)%ref_count = 1
    call system_clock(cache%entries(idx)%last_used)
    cache%entries(idx)%compile_time = compile_time
    cache%entries(idx)%performance = 0.0
    cache%entries(idx)%is_binary_cached = .false.
    cache%entries(idx)%memory_size = 100 * 1024  ! Estimate 100KB
    
    cache%num_entries = cache%num_entries + 1
    
  end subroutine cache_program
  
  ! Find program in cache by key
  function find_program(cache, cache_key) result(idx)
    type(program_cache), intent(in) :: cache
    character(len=*), intent(in) :: cache_key
    integer :: idx
    
    integer :: i
    
    idx = 0
    do i = 1, cache%num_entries
      if (trim(cache%entries(i)%key) == trim(cache_key)) then
        idx = i
        return
      end if
    end do
    
  end function find_program
  
  ! Release reference to program
  subroutine release_program(cache, program_id)
    type(program_cache), intent(inout) :: cache
    integer, intent(in) :: program_id
    
    integer :: i
    
    do i = 1, cache%num_entries
      if (cache%entries(i)%program_id == program_id) then
        cache%entries(i)%ref_count = cache%entries(i)%ref_count - 1
        
        ! Sanity check
        if (cache%entries(i)%ref_count < 0) then
          print *, "WARNING: Negative reference count for program ", program_id
          cache%entries(i)%ref_count = 0
        end if
        
        return
      end if
    end do
    
  end subroutine release_program
  
  ! Evict least recently used program with zero references
  subroutine evict_lru(cache)
    type(program_cache), intent(inout) :: cache
    
    integer :: i, lru_idx
    integer(i64) :: oldest_time
    
    lru_idx = 0
    oldest_time = huge(oldest_time)
    
    ! Find LRU entry with zero references
    do i = 1, cache%num_entries
      if (cache%entries(i)%ref_count == 0 .and. &
          cache%entries(i)%last_used < oldest_time) then
        lru_idx = i
        oldest_time = cache%entries(i)%last_used
      end if
    end do
    
    if (lru_idx == 0) then
      print *, "WARNING: No evictable programs found (all have active references)"
      return
    end if
    
    ! Delete the OpenGL program
    if (cache%entries(lru_idx)%program_id > 0) then
      if (glIsProgram(cache%entries(lru_idx)%program_id) /= 0) then
        call glDeleteProgram(cache%entries(lru_idx)%program_id)
      end if
    end if
    
    print '(A,A)', "♻️  Evicted program: ", trim(cache%entries(lru_idx)%key)
    
    ! Remove entry by shifting others
    do i = lru_idx, cache%num_entries - 1
      cache%entries(i) = cache%entries(i + 1)
    end do
    
    cache%num_entries = cache%num_entries - 1
    
    ! Clear the last entry
    cache%entries(cache%num_entries + 1) = program_cache_entry()
    
  end subroutine evict_lru
  
  ! Clean up cache and delete all programs
  subroutine cleanup_program_cache(cache)
    type(program_cache), intent(inout) :: cache
    
    integer :: i
    
    if (.not. cache%initialized) return
    
    print *, "🧹 Cleaning up GPU program cache..."
    
    ! Delete all OpenGL programs
    do i = 1, cache%num_entries
      if (cache%entries(i)%program_id > 0) then
        if (glIsProgram(cache%entries(i)%program_id) /= 0) then
          call glDeleteProgram(cache%entries(i)%program_id)
        end if
      end if
    end do
    
    ! Print final statistics
    call print_cache_stats(cache)
    
    ! Clear the cache
    deallocate(cache%entries)
    cache%num_entries = 0
    cache%initialized = .false.
    
  end subroutine cleanup_program_cache
  
  ! Print cache statistics
  subroutine print_cache_stats(cache)
    type(program_cache), intent(in) :: cache
    
    real(dp) :: hit_rate, avg_compile_time
    integer(i64) :: total_memory
    integer :: i, active_refs
    
    if (cache%cache_hits + cache%cache_misses > 0) then
      hit_rate = real(cache%cache_hits, real64) / &
                 real(cache%cache_hits + cache%cache_misses, real64) * 100.0
    else
      hit_rate = 0.0
    end if
    
    if (cache%total_compilations > 0) then
      avg_compile_time = real(cache%total_compile_time, real64) / &
                        real(cache%total_compilations, real64) / 1000.0  ! ms
    else
      avg_compile_time = 0.0
    end if
    
    ! Count active references and memory
    active_refs = 0
    total_memory = 0
    do i = 1, cache%num_entries
      active_refs = active_refs + cache%entries(i)%ref_count
      total_memory = total_memory + cache%entries(i)%memory_size
    end do
    
    print *, ""
    print *, "📊 GPU Program Cache Statistics"
    print *, "==============================="
    print '(A,I0,A,I0)', "Programs cached: ", cache%num_entries, " / ", cache%max_entries
    print '(A,I0)', "Active references: ", active_refs
    print '(A,F5.1,A)', "Cache hit rate: ", hit_rate, "%"
    print '(A,I0,A,I0)', "Hits/Misses: ", cache%cache_hits, " / ", cache%cache_misses
    print '(A,I0)', "Total compilations: ", cache%total_compilations
    print '(A,F6.2,A)', "Avg compile time: ", avg_compile_time, " ms"
    print '(A,F6.2,A)', "Total compile time saved: ", &
                       real(cache%cache_hits * avg_compile_time) / 1000.0, " seconds"
    print '(A,F6.2,A)', "Estimated memory usage: ", real(total_memory) / (1024.0 * 1024.0), " MB"
    print *, ""
    
  end subroutine print_cache_stats
  
  ! Get cache statistics (for programmatic access)
  function get_cache_stats(cache) result(stats)
    type(program_cache), intent(in) :: cache
    type :: cache_stats_t
      integer :: num_programs
      integer :: max_programs
      integer :: active_refs
      real(dp) :: hit_rate
      integer(i64) :: total_memory
      real(dp) :: avg_compile_time_ms
    end type cache_stats_t
    type(cache_stats_t) :: stats
    
    integer :: i
    
    stats%num_programs = cache%num_entries
    stats%max_programs = cache%max_entries
    
    if (cache%cache_hits + cache%cache_misses > 0) then
      stats%hit_rate = real(cache%cache_hits, real64) / &
                      real(cache%cache_hits + cache%cache_misses, real64)
    else
      stats%hit_rate = 0.0
    end if
    
    if (cache%total_compilations > 0) then
      stats%avg_compile_time_ms = real(cache%total_compile_time, real64) / &
                                 real(cache%total_compilations, real64) / 1000.0
    else
      stats%avg_compile_time_ms = 0.0
    end if
    
    stats%active_refs = 0
    stats%total_memory = 0
    do i = 1, cache%num_entries
      stats%active_refs = stats%active_refs + cache%entries(i)%ref_count
      stats%total_memory = stats%total_memory + cache%entries(i)%memory_size
    end do
    
  end function get_cache_stats
  
end module gpu_program_cache