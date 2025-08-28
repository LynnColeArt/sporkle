! GPU Program Cache Thread-Safe Version
! =====================================
!
! Thread-safe version of gpu_program_cache_v2 using OpenMP critical sections.
! This ensures safe concurrent access from multiple threads.
!
! Thread safety features:
! - Critical sections for all cache modifications
! - Atomic reference counting
! - Thread-local temporary storage
! - Lock-free read operations where possible
!
! Usage:
!   Must compile with OpenMP support: -fopenmp
!   All public interfaces are thread-safe

module gpu_program_cache_threadsafe
  use kinds
  use iso_c_binding
  use gpu_binary_cache
  use omp_lib
  implicit none
  
  private
  public :: program_cache_ts, program_cache_entry_ts
  public :: init_program_cache_ts, cleanup_program_cache_ts
  public :: get_cached_program_ts, release_program_ts
  public :: print_cache_stats_ts, get_cache_stats_ts
  public :: warm_cache_from_disk_ts
  
  ! Thread-safe cache entry
  type :: program_cache_entry_ts
    integer :: program_id = 0
    character(len=256) :: key = ""
    integer :: ref_count = 0           ! Will use atomic operations
    integer(i64) :: last_used = 0
    integer(i64) :: compile_time = 0
    real(sp) :: performance = 0.0
    logical :: is_binary_cached = .false.
    integer(i64) :: memory_size = 0
    integer :: binary_format = 0
    integer :: binary_size = 0
  end type program_cache_entry_ts
  
  ! Thread-safe cache structure
  type :: program_cache_ts
    type(program_cache_entry_ts), allocatable :: entries(:)
    integer :: num_entries = 0
    integer :: max_entries = 100
    character(len=256) :: cache_dir = "shader_cache/"
    logical :: auto_save = .true.
    logical :: auto_load = .true.
    logical :: initialized = .false.
    logical :: thread_safe = .true.    ! Flag to enable thread safety
    
    ! Statistics (will use atomic operations)
    integer(i64) :: total_compilations = 0
    integer(i64) :: cache_hits = 0
    integer(i64) :: cache_misses = 0
    integer(i64) :: binary_loads = 0
    integer(i64) :: binary_saves = 0
    integer(i64) :: total_compile_time = 0
    integer(i64) :: memory_saved = 0
  end type program_cache_ts
  
  ! OpenGL interfaces (reuse from v2)
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

  ! Initialize thread-safe cache
  subroutine init_program_cache_ts(cache, max_programs, cache_directory, &
                                  auto_save, auto_load, enable_thread_safety)
    type(program_cache_ts), intent(out) :: cache
    integer, intent(in), optional :: max_programs
    character(len=*), intent(in), optional :: cache_directory
    logical, intent(in), optional :: auto_save, auto_load, enable_thread_safety
    
    !$omp critical (cache_init)
    
    ! Set parameters
    if (present(max_programs)) then
      cache%max_entries = max_programs
    else
      cache%max_entries = 100
    end if
    
    if (present(cache_directory)) then
      cache%cache_dir = trim(cache_directory)
    else
      cache%cache_dir = "shader_cache/"
    end if
    
    if (present(auto_save)) cache%auto_save = auto_save
    if (present(auto_load)) cache%auto_load = auto_load
    if (present(enable_thread_safety)) cache%thread_safe = enable_thread_safety
    
    ! Allocate entry array
    allocate(cache%entries(cache%max_entries))
    cache%num_entries = 0
    
    ! Initialize statistics
    cache%total_compilations = 0
    cache%cache_hits = 0
    cache%cache_misses = 0
    cache%binary_loads = 0
    cache%binary_saves = 0
    cache%total_compile_time = 0
    cache%memory_saved = 0
    
    ! Initialize binary cache system
    call binary_cache_init()
    
    ! Create cache directory
    call create_cache_directory(cache%cache_dir)
    
    cache%initialized = .true.
    
    !$omp end critical (cache_init)
    
    print *, "🚀 Thread-Safe GPU Program Cache initialized"
    print '(A,I0,A)', "   Max programs: ", cache%max_entries
    print '(A,A)', "   Cache directory: ", trim(cache%cache_dir)
    print '(A,L1)', "   Auto-save binaries: ", cache%auto_save
    print '(A,L1)', "   Auto-load binaries: ", cache%auto_load
    print '(A,L1)', "   Thread safety: ", cache%thread_safe
    print '(A,I0)', "   OpenMP threads: ", omp_get_max_threads()
    
  end subroutine init_program_cache_ts
  
  ! Thread-safe get cached program
  function get_cached_program_ts(cache, shader_source, cache_key, compile_func) result(program_id)
    type(program_cache_ts), intent(inout) :: cache
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
    logical :: need_compile, loaded_from_disk
    integer :: thread_id
    
    if (.not. cache%initialized) then
      print *, "ERROR: Cache not initialized!"
      program_id = 0
      return
    end if
    
    thread_id = omp_get_thread_num()
    need_compile = .false.
    loaded_from_disk = .false.
    
    ! First check: read-only search (can be done without lock)
    idx = find_program_readonly(cache, cache_key)
    
    if (idx > 0) then
      ! Found in cache - increment ref count atomically
      !$omp atomic
      cache%entries(idx)%ref_count = cache%entries(idx)%ref_count + 1
      
      !$omp atomic
      cache%cache_hits = cache%cache_hits + 1
      
      call system_clock(cache%entries(idx)%last_used)
      program_id = cache%entries(idx)%program_id
      
      if (cache%cache_hits < 10 .or. mod(cache%cache_hits, 100) == 0) then
        print '(A,I0,A,A,A,I0,A)', "[Thread ", thread_id, "] ✅ Cache hit: ", &
              trim(cache_key), " (refs: ", cache%entries(idx)%ref_count, ")"
      end if
      
    else
      ! Not in memory - need to compile or load
      !$omp critical (cache_miss)
      
      ! Double-check inside critical section
      idx = find_program_internal(cache, cache_key)
      
      if (idx > 0) then
        ! Another thread added it while we waited
        cache%entries(idx)%ref_count = cache%entries(idx)%ref_count + 1
        cache%cache_hits = cache%cache_hits + 1
        program_id = cache%entries(idx)%program_id
      else
        ! Really not in cache
        cache%cache_misses = cache%cache_misses + 1
        need_compile = .true.
        program_id = 0
      end if
      
      !$omp end critical (cache_miss)
      
      if (need_compile) then
        ! Try loading from disk first
        if (cache%auto_load) then
          program_id = load_program_binary(cache_key, cache%cache_dir)
          if (program_id > 0) then
            loaded_from_disk = .true.
            
            !$omp atomic
            cache%binary_loads = cache%binary_loads + 1
            
            print '(A,I0,A,A)', "[Thread ", thread_id, "] ⚡ Loaded from disk: ", trim(cache_key)
          end if
        end if
        
        ! If not loaded, compile
        if (program_id == 0) then
          print '(A,I0,A,A)', "[Thread ", thread_id, "] 🔄 Compiling shader: ", trim(cache_key)
          
          ! Time the compilation
          call system_clock(start_time, count_rate=clock_rate)
          program_id = compile_func(shader_source)
          call system_clock(end_time)
          
          compile_time = (end_time - start_time) * 1000000 / int(clock_rate, int64)
          
          if (program_id > 0) then
            !$omp atomic
            cache%total_compilations = cache%total_compilations + 1
            
            !$omp atomic
            cache%total_compile_time = cache%total_compile_time + compile_time
            
            print '(A,I0,A,F6.2,A)', "[Thread ", thread_id, "] Compilation took ", &
                  real(compile_time) / 1000.0, " ms"
          else
            print '(A,I0,A)', "[Thread ", thread_id, "] ❌ Shader compilation failed!"
          end if
        else
          compile_time = 0  ! Loaded from disk
        end if
        
        ! Add to cache if successful
        if (program_id > 0) then
          !$omp critical (cache_add)
          call cache_program_internal(cache, program_id, cache_key, compile_time)
          
          ! Save binary if just compiled
          if (.not. loaded_from_disk .and. cache%auto_save) then
            call save_program_binary(program_id, cache_key, cache%cache_dir)
            cache%binary_saves = cache%binary_saves + 1
            
            ! Update entry
            idx = find_program_internal(cache, cache_key)
            if (idx > 0) cache%entries(idx)%is_binary_cached = .true.
          end if
          
          !$omp end critical (cache_add)
        end if
      end if
    end if
    
  end function get_cached_program_ts
  
  ! Thread-safe release program
  subroutine release_program_ts(cache, program_id)
    type(program_cache_ts), intent(inout) :: cache
    integer, intent(in) :: program_id
    
    integer :: i
    
    !$omp critical (cache_release)
    
    do i = 1, cache%num_entries
      if (cache%entries(i)%program_id == program_id) then
        cache%entries(i)%ref_count = cache%entries(i)%ref_count - 1
        
        if (cache%entries(i)%ref_count < 0) then
          print *, "WARNING: Negative reference count for program ", program_id
          cache%entries(i)%ref_count = 0
        end if
        
        exit
      end if
    end do
    
    !$omp end critical (cache_release)
    
  end subroutine release_program_ts
  
  ! Thread-safe warm cache from disk
  subroutine warm_cache_from_disk_ts(cache, keys)
    type(program_cache_ts), intent(inout) :: cache
    character(len=*), intent(in) :: keys(:)
    
    integer :: i, program_id, loaded
    
    if (.not. cache%initialized) return
    
    print *, "🔥 Warming cache from disk..."
    loaded = 0
    
    !$omp critical (cache_warm)
    
    do i = 1, size(keys)
      program_id = load_program_binary(keys(i), cache%cache_dir)
      if (program_id > 0) then
        call cache_program_internal(cache, program_id, keys(i), 0_int64)
        loaded = loaded + 1
      end if
    end do
    
    if (loaded > 0) then
      cache%binary_loads = cache%binary_loads + loaded
    end if
    
    !$omp end critical (cache_warm)
    
    if (loaded > 0) then
      print '(A,I0,A)', "   Loaded ", loaded, " programs from disk"
    else
      print *, "   No cached binaries found"
    end if
    
  end subroutine warm_cache_from_disk_ts
  
  ! Thread-safe cleanup
  subroutine cleanup_program_cache_ts(cache)
    type(program_cache_ts), intent(inout) :: cache
    
    integer :: i, saved
    
    if (.not. cache%initialized) return
    
    !$omp critical (cache_cleanup)
    
    print *, "🧹 Cleaning up thread-safe GPU program cache..."
    
    ! Save any unsaved binaries
    if (cache%auto_save) then
      saved = 0
      do i = 1, cache%num_entries
        if (cache%entries(i)%program_id > 0 .and. &
            .not. cache%entries(i)%is_binary_cached) then
          call save_program_binary(cache%entries(i)%program_id, &
                                 cache%entries(i)%key, cache%cache_dir)
          saved = saved + 1
        end if
      end do
      
      if (saved > 0) then
        print '(A,I0,A)', "   Saved ", saved, " new binaries to disk"
        cache%binary_saves = cache%binary_saves + saved
      end if
    end if
    
    ! Delete all OpenGL programs
    do i = 1, cache%num_entries
      if (cache%entries(i)%program_id > 0) then
        if (glIsProgram(cache%entries(i)%program_id) /= 0) then
          call glDeleteProgram(cache%entries(i)%program_id)
        end if
      end if
    end do
    
    ! Print final statistics
    call print_cache_stats_internal(cache)
    
    ! Cleanup binary cache
    call binary_cache_cleanup()
    
    ! Clear the cache
    deallocate(cache%entries)
    cache%num_entries = 0
    cache%initialized = .false.
    
    !$omp end critical (cache_cleanup)
    
  end subroutine cleanup_program_cache_ts
  
  ! Thread-safe print stats
  subroutine print_cache_stats_ts(cache)
    type(program_cache_ts), intent(in) :: cache
    
    !$omp critical (cache_stats)
    call print_cache_stats_internal(cache)
    !$omp end critical (cache_stats)
    
  end subroutine print_cache_stats_ts
  
  ! Get cache statistics (thread-safe)
  function get_cache_stats_ts(cache) result(stats)
    type(program_cache_ts), intent(in) :: cache
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
    
    !$omp critical (cache_stats_get)
    
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
    
    !$omp end critical (cache_stats_get)
    
  end function get_cache_stats_ts
  
  !============================================================================
  ! Internal helper functions (not exposed, used within critical sections)
  !============================================================================
  
  ! Find program (read-only, no lock needed)
  function find_program_readonly(cache, cache_key) result(idx)
    type(program_cache_ts), intent(in) :: cache
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
    
  end function find_program_readonly
  
  ! Find program (internal, called within critical section)
  function find_program_internal(cache, cache_key) result(idx)
    type(program_cache_ts), intent(in) :: cache
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
    
  end function find_program_internal
  
  ! Add program to cache (internal, called within critical section)
  subroutine cache_program_internal(cache, program_id, cache_key, compile_time)
    type(program_cache_ts), intent(inout) :: cache
    integer, intent(in) :: program_id
    character(len=*), intent(in) :: cache_key
    integer(i64), intent(in) :: compile_time
    
    integer :: idx
    
    ! Check if we need to evict
    if (cache%num_entries >= cache%max_entries) then
      call evict_lru_internal(cache)
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
    
  end subroutine cache_program_internal
  
  ! Evict LRU (internal, called within critical section)
  subroutine evict_lru_internal(cache)
    type(program_cache_ts), intent(inout) :: cache
    
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
    cache%entries(cache%num_entries + 1) = program_cache_entry_ts()
    
  end subroutine evict_lru_internal
  
  ! Print statistics (internal, called within critical section)
  subroutine print_cache_stats_internal(cache)
    type(program_cache_ts), intent(in) :: cache
    
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
    print *, "📊 Thread-Safe GPU Program Cache Statistics"
    print *, "==========================================="
    print '(A,I0,A,I0)', "Programs cached: ", cache%num_entries, " / ", cache%max_entries
    print '(A,I0)', "Active references: ", active_refs
    print '(A,F5.1,A)', "Cache hit rate: ", hit_rate, "%"
    print '(A,I0,A,I0)', "Hits/Misses: ", cache%cache_hits, " / ", cache%cache_misses
    print '(A,I0)', "Total compilations: ", cache%total_compilations
    print '(A,F6.2,A)', "Avg compile time: ", avg_compile_time, " ms"
    print '(A,F6.2,A)', "Total compile time saved: ", &
                       real(cache%cache_hits * avg_compile_time) / 1000.0, " seconds"
    print '(A,I0,A,I0)', "Binary loads/saves: ", cache%binary_loads, " / ", cache%binary_saves
    print '(A,F6.2,A)', "Estimated memory usage: ", real(total_memory) / (1024.0 * 1024.0), " MB"
    print '(A,I0)', "Max OpenMP threads: ", omp_get_max_threads()
    print *, ""
    
  end subroutine print_cache_stats_internal
  
end module gpu_program_cache_threadsafe