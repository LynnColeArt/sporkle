> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Fortran Shader Parser Design (Pure Fortran Implementation)

## Overview
A pure Fortran parser that translates annotated Fortran kernels to GLSL compute shaders.

## Module Structure

### 1. sporkle_shader_parser.f90
```fortran
module sporkle_shader_parser
  use iso_fortran_env
  use sporkle_types
  implicit none

  type :: shader_kernel
    character(len=256) :: name
    integer :: local_size_x = 64
    integer :: local_size_y = 1
    integer :: local_size_z = 1
    integer :: num_inputs = 0
    integer :: num_outputs = 0
    character(len=1024) :: body
    ! Extracted metadata
    type(kernel_arg), allocatable :: args(:)
  end type

  type :: kernel_arg
    character(len=64) :: name
    character(len=32) :: type_str  ! "integer(int32)", "real(real32)", etc
    character(len=16) :: intent    ! "in", "out", "inout", "value"
    integer :: binding_slot
  end type

contains
  function parse_fortran_kernel(filename, kernel_name) result(kernel)
    character(len=*), intent(in) :: filename, kernel_name
    type(shader_kernel) :: kernel
    ! Implementation below
  end function

  function generate_glsl(kernel) result(glsl_source)
    type(shader_kernel), intent(in) :: kernel
    character(len=:), allocatable :: glsl_source
    ! Implementation below
  end function
end module
```

### 2. Parsing Strategy

```fortran
function parse_fortran_kernel(filename, kernel_name) result(kernel)
  character(len=*), intent(in) :: filename, kernel_name
  type(shader_kernel) :: kernel
  character(len=512) :: line
  logical :: in_kernel = .false.
  integer :: unit, iostat
  
  open(newunit=unit, file=filename, status='old', action='read')
  
  do
    read(unit, '(A)', iostat=iostat) line
    if (iostat /= 0) exit
    
    ! Look for kernel annotation
    if (index(line, "!@kernel") > 0) then
      call parse_kernel_annotation(line, kernel)
      in_kernel = .true.
      cycle
    end if
    
    ! Parse subroutine signature
    if (in_kernel .and. index(line, "subroutine") > 0) then
      if (index(line, trim(kernel_name)) > 0) then
        call parse_subroutine_signature(line, kernel)
      end if
    end if
    
    ! Collect body
    if (in_kernel) then
      kernel%body = trim(kernel%body) // trim(line) // NEW_LINE('A')
      if (index(line, "end subroutine") > 0) exit
    end if
  end do
  
  close(unit)
end function
```

### 3. GLSL Generation

```fortran
function generate_glsl(kernel) result(glsl_source)
  type(shader_kernel), intent(in) :: kernel
  character(len=:), allocatable :: glsl_source
  character(len=4096) :: buffer
  integer :: i
  
  ! Header
  buffer = "#version 310 es" // NEW_LINE('A')
  write(buffer, '(A,A,I0,A,I0,A)') trim(buffer), &
    "layout(local_size_x = ", kernel%local_size_x, &
    ", local_size_y = ", kernel%local_size_y, ") in;" // NEW_LINE('A')
  
  ! Buffer bindings
  do i = 1, size(kernel%args)
    if (kernel%args(i)%intent /= "value") then
      buffer = trim(buffer) // generate_buffer_binding(kernel%args(i))
    end if
  end do
  
  ! Main function
  buffer = trim(buffer) // NEW_LINE('A') // "void main() {" // NEW_LINE('A')
  buffer = trim(buffer) // "  uint i = gl_GlobalInvocationID.x;" // NEW_LINE('A')
  
  ! Translate body (simplified)
  buffer = trim(buffer) // translate_fortran_body(kernel%body)
  
  buffer = trim(buffer) // "}" // NEW_LINE('A')
  
  glsl_source = trim(buffer)
end function
```

### 4. Helper Functions

```fortran
subroutine parse_kernel_annotation(line, kernel)
  character(len=*), intent(in) :: line
  type(shader_kernel), intent(inout) :: kernel
  integer :: pos, eq_pos
  character(len=64) :: param_name, param_value
  
  ! Extract parameters from !@kernel(local_size_x=64, out=1, ...)
  pos = index(line, "(")
  ! ... parse comma-separated key=value pairs ...
end subroutine

function fortran_type_to_glsl(fortran_type) result(glsl_type)
  character(len=*), intent(in) :: fortran_type
  character(len=32) :: glsl_type
  
  select case(trim(fortran_type))
  case("integer(int32)")
    glsl_type = "uint"
  case("real(real32)")
    glsl_type = "float"
  case("real(real64)")
    glsl_type = "double"
  ! ... etc
  end select
end function
```

## Usage Example

```fortran
program test_parser
  use sporkle_shader_parser
  use sporkle_glsl_compute
  
  type(shader_kernel) :: kernel
  character(len=:), allocatable :: glsl_source
  
  ! Parse Fortran kernel
  kernel = parse_fortran_kernel("kernels.f90", "store_deadbeef")
  
  ! Generate GLSL
  glsl_source = generate_glsl(kernel)
  
  ! Compile and run (using existing infrastructure)
  call compile_and_dispatch_glsl(glsl_source, N, buffers)
end program
```

## Key Design Decisions

1. **Simple line-based parsing** - No full AST needed for MVP
2. **Limited subset** - Only parse what we support
3. **Direct translation** - Fortran expressions → GLSL with minimal transformation
4. **Reuse existing infrastructure** - Plug into our working GLSL compute path
5. **Pure Fortran** - No external dependencies

This gives us a working Fortran shader system TODAY!