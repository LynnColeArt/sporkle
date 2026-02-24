module sporkle_conv2d_unified
  ! Unified Conv2D implementation - selects CPU or Kronos runtime intent
  ! Production intent: GPU work currently must arrive through Kronos-native dispatch
  
  use kinds
  use cpu_device_module
  use cpu_conv2d_adaptive
  implicit none
  private
  
  public :: sporkle_conv2d_unified
  
contains

  function sporkle_conv2d_unified(input, weights, output, &
                                 N, C, H, W, K, kernel_size, stride, pad, &
                                 device_type) result(time_ms)
    real(sp), intent(in) :: input(:), weights(:)
    real(sp), intent(out) :: output(:)
    integer, intent(in) :: N, C, H, W, K, kernel_size, stride, pad
    character(len=*), intent(in), optional :: device_type
    real(sp) :: time_ms
    
    character(len=16) :: device_choice
    integer :: H_out, W_out
    
    ! Calculate output dimensions
    H_out = (H + 2*pad - kernel_size) / stride + 1
    W_out = (W + 2*pad - kernel_size) / stride + 1
    
    ! Determine device
    if (present(device_type)) then
      device_choice = device_type
    else
      device_choice = "auto"
    end if
    
    select case(trim(device_choice))
    case("cpu")
      time_ms = execute_cpu_conv2d()
    case("gpu", "kronos")
      print *, "❌ GPU execution is not supported in this recovery path."
      print *, "   Use device_type='cpu' or unset device_id for explicit CPU routing."
      print *, "   Kronos-native dispatch must be active for GPU execution."
      error stop "Kronos-native Conv2D GPU dispatch is not yet wired in this API path."
    case("auto")
      if (N * H_out * W_out * K > 1000000) then
        print *, "⚠️  Auto-routing to CPU; GPU runtime remains recovery-disabled by policy."
      end if
      time_ms = execute_cpu_conv2d()
    case default
      print *, "❌ Unknown device type: ", trim(device_choice)
      print *, "   Supported: cpu, kronos, auto"
      print *, "   Unknown backends are treated as hard-fail to prevent silent fallback."
      error stop "sporkle_conv2d_unified received unsupported device type."
    end select
    
  contains
  
    function execute_cpu_conv2d() result(time_ms)
      real(sp) :: time_ms
      type(cpu_device) :: cpu_dev
      
      print *, "🔧 Executing Conv2D on CPU..."
      cpu_dev = cpu_device(0)
      
      ! Use adaptive CPU implementation
      time_ms = conv2d_adaptive(input, weights, output, &
                               N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
      
      if (time_ms > 0.0_sp) then
        print '(A,F8.2,A)', "✅ CPU Conv2D completed in ", time_ms, " ms"
      end if
      
    end function execute_cpu_conv2d
    
  end function sporkle_conv2d_unified

end module sporkle_conv2d_unified
