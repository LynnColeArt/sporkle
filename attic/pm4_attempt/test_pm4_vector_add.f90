program test_pm4_vector_add
  use kinds
  use sporkle_pm4_compute
  use sporkle_amdgpu_direct
  implicit none
  
  logical :: success
  integer :: i, n
  real(sp), allocatable :: a(:), b(:), c(:), expected(:)
  real(sp) :: time_ms
  real(sp) :: max_error
  
  print *, "🧪 PM4 Vector Add Test"
  print *, "======================"
  print *, ""
  
  ! Initialize PM4 compute
  print *, "🚀 Initializing PM4 compute..."
  success = pm4_init_compute()
  if (.not. success) then
    print *, "❌ Failed to initialize PM4 compute"
    stop 1
  end if
  print *, ""
  
  ! Test sizes
  do n = 16, 256, 240
    print '(A,I0,A)', "📊 Testing vector add with ", n, " elements"
    
    allocate(a(n), b(n), c(n), expected(n))
    
    ! Initialize test data
    do i = 1, n
      a(i) = real(i)
      b(i) = real(i * 2)
      expected(i) = a(i) + b(i)
    end do
    c = 0.0
    
    ! Run vector add on GPU
    time_ms = pm4_vector_add(a, b, c, n)
    
    if (time_ms >= 0.0) then
      print '(A,F0.3,A)', "   ✅ Completed in ", time_ms, " ms"
      
      ! Check results
      max_error = 0.0
      do i = 1, n
        max_error = max(max_error, abs(c(i) - expected(i)))
      end do
      
      if (max_error < 1e-5) then
        print *, "   ✅ Results correct!"
      else
        print '(A,E12.5)', "   ❌ Max error: ", max_error
        print *, "   First few results:"
        do i = 1, min(5, n)
          print '(A,I3,A,F8.2,A,F8.2,A,F8.2)', &
                "     [", i, "] ", a(i), " + ", b(i), " = ", c(i)
        end do
      end if
    else
      print *, "   ❌ Vector add failed"
    end if
    
    deallocate(a, b, c, expected)
    print *, ""
  end do
  
  ! Cleanup
  print *, "🧹 Cleaning up..."
  call pm4_cleanup_compute()
  
  print *, ""
  print *, "✅ PM4 vector add test complete!"
  
contains

  ! Simple vector add using PM4
  function pm4_vector_add(a, b, c, n) result(time_ms)
    real(sp), intent(in) :: a(:), b(:)
    real(sp), intent(out) :: c(:)
    integer, intent(in) :: n
    real(sp) :: time_ms
    
    type(amdgpu_buffer) :: buf_a, buf_b, buf_c
    integer(i64) :: shader_addr
    integer :: status
    integer :: grid_size
    
    time_ms = -1.0
    
    ! Compile shader
    shader_addr = pm4_compile_shader("vector_add", "")
    if (shader_addr == 0) then
      print *, "❌ Failed to compile vector add shader"
      return
    end if
    
    ! Allocate buffers
    buf_a = amdgpu_allocate_buffer(g_context%device, &
                                  int(n * 4, int64), &
                                  AMDGPU_GEM_DOMAIN_GTT)
    if (buf_a%handle == 0) return
    
    buf_b = amdgpu_allocate_buffer(g_context%device, &
                                  int(n * 4, int64), &
                                  AMDGPU_GEM_DOMAIN_GTT)
    if (buf_b%handle == 0) return
    
    buf_c = amdgpu_allocate_buffer(g_context%device, &
                                  int(n * 4, int64), &
                                  AMDGPU_GEM_DOMAIN_GTT)
    if (buf_c%handle == 0) return
    
    ! Map buffers for CPU access
    status = amdgpu_map_buffer(g_context%device, buf_a)
    if (status /= 0) return
    
    status = amdgpu_map_buffer(g_context%device, buf_b)
    if (status /= 0) return
    
    status = amdgpu_map_buffer(g_context%device, buf_c)
    if (status /= 0) return
    
    ! Map to GPU VA
    buf_a%va_addr = gpu_va_allocate(buf_a%size)
    status = amdgpu_map_va(g_context%device, buf_a, buf_a%va_addr)
    if (status /= 0) return
    
    buf_b%va_addr = gpu_va_allocate(buf_b%size)
    status = amdgpu_map_va(g_context%device, buf_b, buf_b%va_addr)
    if (status /= 0) return
    
    buf_c%va_addr = gpu_va_allocate(buf_c%size)
    status = amdgpu_map_va(g_context%device, buf_c, buf_c%va_addr)
    if (status /= 0) return
    
    ! Copy input data
    block
      real(sp), pointer :: ptr(:)
      
      call c_f_pointer(buf_a%cpu_ptr, ptr, [n])
      ptr = a
      
      call c_f_pointer(buf_b%cpu_ptr, ptr, [n])
      ptr = b
    end block
    
    ! Execute shader
    grid_size = (n + 63) / 64  ! 64 threads per group
    
    time_ms = pm4_execute_compute(shader_addr, &
                                 64, 1, 1, &  ! threads per group
                                 grid_size, 1, 1, &  ! grid dimensions
                                 [buf_a, buf_b, buf_c], 3)
    
    ! Copy output data
    if (time_ms >= 0.0) then
      block
        real(sp), pointer :: ptr(:)
        call c_f_pointer(buf_c%cpu_ptr, ptr, [n])
        c = ptr
      end block
    end if
    
    ! TODO: Free buffers
    
  end function pm4_vector_add
  
  ! Need to access global context
  type :: pm4_compute_context
    type(amdgpu_device) :: device
  end type pm4_compute_context
  
  type(pm4_compute_context), external :: g_context
  integer, parameter :: AMDGPU_GEM_DOMAIN_GTT = 2
  
end program test_pm4_vector_add