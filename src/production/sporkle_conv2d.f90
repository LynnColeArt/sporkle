! Production interface for convolution operations.
! This module is intentionally CPU-first while GPU acceleration is
! tracked in separate recovery work.

module sporkle_conv2d
  use kinds
  use cpu_conv2d_adaptive, only: conv2d_adaptive
  implicit none
  
  private
  public :: conv2d_cpu, conv2d_gpu, conv2d_auto
  public :: conv2d_select_implementation
  
  ! Implementation selection
  character(len=64) :: cpu_impl = "adaptive"
  character(len=64) :: gpu_impl = "reference"
  
contains
  
  subroutine conv2d_cpu(input, weights, output, &
                       N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
    real(sp), intent(in) :: input(:), weights(:)
    real(sp), intent(out) :: output(:)
    integer, intent(in) :: N, C, H, W, K, kernel_size, stride, pad, H_out, W_out
    
    real(sp) :: time_ms
    
    select case(cpu_impl)
    case("adaptive")
      time_ms = conv2d_adaptive(input, weights, output, &
                               N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
    case("reference", "fused")
      time_ms = conv2d_adaptive(input, weights, output, &
                               N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
    
    case("naive")
      time_ms = conv2d_adaptive(input, weights, output, &
                               N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
    case default
      print *, "Unknown CPU implementation: ", trim(cpu_impl)
      stop
    end select
  end subroutine conv2d_cpu
  
  subroutine conv2d_gpu(input, weights, output, &
                       N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
    real(sp), intent(in) :: input(:), weights(:)
    real(sp), intent(out) :: output(:)
    integer, intent(in) :: N, C, H, W, K, kernel_size, stride, pad, H_out, W_out
    
    print *, "❌ conv2d_gpu is disabled in this recovery profile."
    print *, "   Use conv2d_auto with CPU fallback or direct CPU path until Kronos dispatch is active."
    error stop "Kronos-native conv2d GPU dispatch is not yet active in this module."
  end subroutine conv2d_gpu
  
  subroutine conv2d_auto(input, weights, output, &
                        N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
    real(sp), intent(in) :: input(:), weights(:)
    real(sp), intent(out) :: output(:)
    integer, intent(in) :: N, C, H, W, K, kernel_size, stride, pad, H_out, W_out
    
    ! Auto-select policy: CPU only in this recovery profile.
    call conv2d_cpu(input, weights, output, &
                    N, C, H, W, K, kernel_size, stride, pad, H_out, W_out)
  end subroutine conv2d_auto
  
  subroutine conv2d_select_implementation(device, impl_name)
    character(len=*), intent(in) :: device, impl_name
    
    select case(device)
    case("cpu")
      cpu_impl = impl_name
      print *, "CPU implementation set to: ", trim(cpu_impl)
    case("gpu")  
      gpu_impl = impl_name
      print *, "GPU implementation set to: ", trim(gpu_impl)
      print *, "⚠️  GPU execution remains disabled in this recovery profile."
    case default
      print *, "Unknown device: ", trim(device)
    end select
  end subroutine conv2d_select_implementation
  
end module sporkle_conv2d
