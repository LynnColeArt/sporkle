program test_kronos_basic
  use iso_c_binding
  use kinds
  use sporkle_kronos_ffi
  implicit none
  
  type(kronos_context) :: ctx
  type(kronos_buffer) :: buffer_a, buffer_b
  integer :: status
  type(c_ptr) :: data_ptr
  real(sp), pointer :: data(:)
  integer :: i
  integer(c_size_t) :: buffer_size
  
  print *, "=== Kronos Basic FFI Test ==="
  
  ! Test 1: Context creation
  print *, "Test 1: Creating Kronos context..."
  ctx = kronos_init()
  
  if (c_associated(ctx%handle)) then
    print *, "✅ Context created successfully"
  else
    print *, "❌ Failed to create context"
    stop 1
  end if
  
  ! Test 2: Buffer allocation
  print *, ""
  print *, "Test 2: Allocating buffers..."
  buffer_size = 1000 * 4_c_size_t  ! 1000 floats
  
  buffer_a = kronos_create_buffer(ctx, buffer_size)
  if (c_associated(buffer_a%handle)) then
    print *, "✅ Buffer A allocated (", buffer_size, "bytes)"
  else
    print *, "❌ Failed to allocate buffer A"
    stop 1
  end if
  
  buffer_b = kronos_create_buffer(ctx, buffer_size)
  if (c_associated(buffer_b%handle)) then
    print *, "✅ Buffer B allocated (", buffer_size, "bytes)"
  else
    print *, "❌ Failed to allocate buffer B"
    stop 1
  end if
  
  ! Test 3: Buffer mapping and data write
  print *, ""
  print *, "Test 3: Mapping buffer and writing data..."
  status = kronos_map_buffer(ctx, buffer_a, data_ptr)
  
  if (status == KRONOS_SUCCESS .and. c_associated(data_ptr)) then
    print *, "✅ Buffer mapped successfully"
    
    ! Write test data
    call c_f_pointer(data_ptr, data, [1000])
    do i = 1, 1000
      data(i) = real(i, sp)
    end do
    
    call kronos_unmap_buffer(ctx, buffer_a)
    print *, "✅ Data written and buffer unmapped"
  else
    print *, "❌ Failed to map buffer"
  end if
  
  ! Test 4: Verify we can re-map and read data
  print *, ""
  print *, "Test 4: Re-mapping and verifying data..."
  status = kronos_map_buffer(ctx, buffer_a, data_ptr)
  
  if (status == KRONOS_SUCCESS .and. c_associated(data_ptr)) then
    call c_f_pointer(data_ptr, data, [1000])
    
    ! Check first few values
    if (data(1) == 1.0_sp .and. data(2) == 2.0_sp .and. data(1000) == 1000.0_sp) then
      print *, "✅ Data verification passed"
      print *, "   data(1) =", data(1)
      print *, "   data(2) =", data(2)
      print *, "   data(1000) =", data(1000)
    else
      print *, "❌ Data verification failed"
    end if
    
    call kronos_unmap_buffer(ctx, buffer_a)
  else
    print *, "❌ Failed to re-map buffer"
  end if
  
  ! Test 5: Pipeline creation (with dummy SPIR-V)
  print *, ""
  print *, "Test 5: Pipeline creation test..."
  block
    ! Minimal valid SPIR-V header (just enough to test the API)
    integer(c_int32_t) :: spirv_header(5)
    type(kronos_pipeline) :: pipeline
    
    ! SPIR-V magic number and basic header
    spirv_header(1) = int(z'07230203', c_int32_t)  ! Magic number
    spirv_header(2) = int(z'00010000', c_int32_t)  ! Version 1.0
    spirv_header(3) = 0  ! Generator
    spirv_header(4) = 1  ! Bound
    spirv_header(5) = 0  ! Schema
    
    pipeline = kronos_create_pipeline(ctx, &
                                     transfer(spirv_header, [1_c_int8_t]), &
                                     int(5 * 4, c_size_t))
    
    if (c_associated(pipeline%handle)) then
      print *, "✅ Pipeline created (will fail validation, but API works)"
    else
      print *, "⚠️  Pipeline creation returned null (expected for invalid SPIR-V)"
    end if
  end block
  
  ! Cleanup
  print *, ""
  print *, "Test 6: Cleanup..."
  call kronos_cleanup(ctx)
  print *, "✅ Context cleaned up"
  
  print *, ""
  print *, "=== All basic FFI tests complete! ==="
  print *, ""
  print *, "Next steps:"
  print *, "1. Build Rust library with: cargo build --release"
  print *, "2. Link with -L./target/release -lsporkle_kronos -lvulkan"
  print *, "3. Create proper SPIR-V shaders for compute"
  
end program test_kronos_basic