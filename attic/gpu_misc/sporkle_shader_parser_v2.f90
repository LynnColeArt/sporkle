module sporkle_shader_parser_v2
  ! Enhanced Fortran shader parser with adaptive parameter passing support
  use kinds
  use iso_c_binding
  use sporkle_fortran_params, only: PARAM_BUFFER_BINDING, PARAMS_UNIFORM, PARAMS_BUFFER, PARAMS_INLINE
  implicit none
  private
  
  public :: shader_kernel_v2, kernel_arg_v2, kernel_param
  public :: parse_fortran_kernel_v2, generate_glsl_v2
  
  type :: kernel_param
    character(len=64) :: name = ""
    character(len=32) :: type_str = ""    ! "integer(i32)", "real(sp)", etc
    integer :: param_index = -1           ! Index in params array
  end type kernel_param
  
  type :: kernel_arg_v2
    character(len=64) :: name = ""
    character(len=32) :: type_str = ""    ! "integer(i32)", "real(sp)", etc
    character(len=16) :: intent = ""      ! "in", "out", "inout", "value"
    integer :: binding_slot = -1
    logical :: is_scalar = .false.        ! True for value parameters
  end type kernel_arg_v2
  
  type :: shader_kernel_v2
    character(len=256) :: name = ""
    integer :: local_size_x = 64
    integer :: local_size_y = 1
    integer :: local_size_z = 1
    integer :: num_inputs = 0
    integer :: num_outputs = 0
    character(len=4096) :: body = ""
    type(kernel_arg_v2), allocatable :: args(:)
    type(kernel_param), allocatable :: params(:)  ! Scalar parameters
    integer :: param_method = PARAMS_BUFFER        ! Default method
  end type shader_kernel_v2

contains

  function parse_fortran_kernel_v2(filename, kernel_name, param_method) result(kernel)
    character(len=*), intent(in) :: filename, kernel_name
    integer, intent(in), optional :: param_method
    type(shader_kernel_v2) :: kernel
    character(len=512) :: line
    character(len=8192) :: kernel_text
    logical :: in_kernel = .false.
    logical :: found_kernel = .false.
    integer :: unit, iostat, i
    
    kernel%name = kernel_name
    if (present(param_method)) kernel%param_method = param_method
    kernel_text = ""
    
    open(newunit=unit, file=filename, status='old', action='read', iostat=iostat)
    if (iostat /= 0) then
      print *, "Error opening file: ", filename
      return
    end if
    
    ! Read the entire kernel into a string
    do
      read(unit, '(A)', iostat=iostat) line
      if (iostat /= 0) exit
      
      ! Look for kernel annotation
      if (index(line, "!@kernel") > 0) then
        call parse_kernel_annotation_v2(line, kernel)
        in_kernel = .true.
      end if
      
      ! Look for kernel subroutine and start collecting text
      if (in_kernel .and. .not. found_kernel .and. index(line, "subroutine " // trim(kernel_name)) > 0) then
        found_kernel = .true.
        kernel_text = trim(line) // NEW_LINE('A')  ! Start with the subroutine line
      else if (found_kernel) then
        ! Continue collecting kernel text
        kernel_text = trim(kernel_text) // trim(line) // NEW_LINE('A')
        if (index(line, "end subroutine") > 0) exit
      end if
    end do
    
    close(unit)
    
    ! Parse the collected kernel text
    if (found_kernel) then
      call parse_kernel_text_v2(kernel_text, kernel)
    else
      print *, "Error: Kernel ", trim(kernel_name), " not found"
    end if
    
    ! Separate params from args and assign indices
    call organize_parameters(kernel)
    
    
  end function parse_fortran_kernel_v2

  subroutine parse_kernel_annotation_v2(line, kernel)
    character(len=*), intent(in) :: line
    type(shader_kernel_v2), intent(inout) :: kernel
    integer :: start_pos, end_pos, eq_pos, comma_pos
    character(len=64) :: param_str, value
    
    ! Same as original, just reusing code
    start_pos = index(line, "(")
    end_pos = index(line, ")")
    
    if (start_pos > 0 .and. end_pos > start_pos) then
      param_str = line(start_pos+1:end_pos-1)
      
      ! Parse local_size_x if present
      eq_pos = index(param_str, "local_size_x=")
      if (eq_pos > 0) then
        value = param_str(eq_pos+13:)
        comma_pos = index(value, ",")
        if (comma_pos > 0) value = value(1:comma_pos-1)
        read(value, *) kernel%local_size_x
      end if
      
      ! Parse out= for number of outputs
      eq_pos = index(param_str, "out=")
      if (eq_pos > 0) then
        value = param_str(eq_pos+4:)
        comma_pos = index(value, ",")
        if (comma_pos > 0) value = value(1:comma_pos-1)
        read(value, *) kernel%num_outputs
      end if
      
      ! Parse in= for number of inputs  
      eq_pos = index(param_str, "in=")
      if (eq_pos > 0) then
        value = param_str(eq_pos+3:)
        comma_pos = index(value, ",")
        if (comma_pos > 0) value = value(1:comma_pos-1)
        read(value, *) kernel%num_inputs
      end if
    end if
  end subroutine parse_kernel_annotation_v2

  subroutine parse_kernel_text_v2(text, kernel)
    character(len=*), intent(in) :: text
    type(shader_kernel_v2), intent(inout) :: kernel
    character(len=2048) :: line, full_signature
    integer :: i, newline_pos, arg_idx
    logical :: found_body, in_declarations, in_signature
    
    i = 1
    found_body = .false.
    in_declarations = .false.
    in_signature = .false.
    full_signature = ""
    
    
    ! Process line by line
    do while (i <= len_trim(text))
      ! Extract line
      newline_pos = index(text(i:), NEW_LINE('A'))
      if (newline_pos > 0) then
        line = text(i:i+newline_pos-2)
        i = i + newline_pos
      else
        line = text(i:)
        i = len_trim(text) + 1
      end if
      
      ! Skip empty lines
      if (len_trim(line) == 0) cycle
      
      
      ! Parse subroutine signature (exclude "end subroutine")
      if (index(line, "subroutine") > 0 .and. index(line, trim(kernel%name)) > 0 .and. &
          index(line, "end subroutine") == 0) then
        in_signature = .true.
        full_signature = trim(line)
        ! Check if line ends with continuation character
        if (index(line, "&") > 0) then
          ! Remove trailing ampersand and spaces
          block
            integer :: amp_pos
            amp_pos = index(line, "&", .true.)
            if (amp_pos > 0) then
              full_signature = line(1:amp_pos-1)
            else
              full_signature = line
            end if
          end block
          ! Continue reading signature
          cycle
        else
          ! Single line signature
          call parse_subroutine_signature_from_line_v2(full_signature, kernel)
          in_declarations = .true.
          in_signature = .false.
        end if
      
      ! Continue reading multi-line signature
      else if (in_signature) then
        ! Append to signature, handling leading ampersand
        block
          character(len=512) :: clean_line
          clean_line = adjustl(line)
          if (len_trim(clean_line) > 0 .and. clean_line(1:1) == "&") then
            clean_line = adjustl(clean_line(2:))
          end if
          full_signature = trim(full_signature) // " " // trim(clean_line)
        end block
        
        ! Check if we're done with the signature (no trailing ampersand)
        if (index(line, "&") == 0 .or. index(line, ")") > 0) then
          call parse_subroutine_signature_from_line_v2(full_signature, kernel)
          in_declarations = .true.
          in_signature = .false.
        else
          ! Remove trailing ampersand for next iteration
          block
            integer :: amp_pos
            amp_pos = index(full_signature, "&", .true.)
            if (amp_pos > 0) then
              full_signature = full_signature(1:amp_pos-1)
            end if
          end block
        end if
      
      ! Parse declarations
      else if (in_declarations .and. index(line, "::") > 0) then
        call parse_declaration_line_v2(line, kernel)
      
      ! Skip use statements and comments
      else if (index(line, "use ") > 0 .or. index(adjustl(line), "!") == 1) then
        continue
      
      ! End of subroutine
      else if (index(line, "end subroutine") > 0) then
        exit
      
      ! Body code
      else if (in_declarations) then
        found_body = .true.
        kernel%body = trim(kernel%body) // trim(adjustl(line)) // NEW_LINE('A')
      end if
    end do
  end subroutine parse_kernel_text_v2
  
  subroutine parse_subroutine_signature_from_line_v2(line, kernel)
    character(len=*), intent(in) :: line
    type(shader_kernel_v2), intent(inout) :: kernel
    character(len=64), allocatable :: arg_names(:)
    integer :: paren_start, paren_end, num_args, i
    
    ! Extract argument list
    paren_start = index(line, "(")
    paren_end = index(line, ")")
    
    if (paren_start > 0 .and. paren_end > paren_start) then
      call parse_argument_list_v2(line(paren_start+1:paren_end-1), arg_names, num_args)
      
      ! Allocate args array
      if (allocated(kernel%args)) deallocate(kernel%args)
      allocate(kernel%args(num_args))
      
      ! Set arg names
      do i = 1, num_args
        kernel%args(i)%name = arg_names(i)
      end do
    end if
  end subroutine parse_subroutine_signature_from_line_v2

  subroutine parse_argument_list_v2(arg_string, arg_names, num_args)
    character(len=*), intent(in) :: arg_string
    character(len=64), allocatable, intent(out) :: arg_names(:)
    integer, intent(out) :: num_args
    integer :: i, comma_pos
    character(len=512) :: work_str
    
    ! Count commas to determine number of args
    num_args = 1
    do i = 1, len_trim(arg_string)
      if (arg_string(i:i) == ',') num_args = num_args + 1
    end do
    
    allocate(arg_names(num_args))
    
    ! Parse each argument
    work_str = adjustl(arg_string)
    do i = 1, num_args
      comma_pos = index(work_str, ",")
      if (comma_pos > 0) then
        arg_names(i) = adjustl(work_str(1:comma_pos-1))
        work_str = adjustl(work_str(comma_pos+1:))
      else
        arg_names(i) = adjustl(work_str(1:min(64,len_trim(work_str))))
      end if
    end do
  end subroutine parse_argument_list_v2

  subroutine parse_declaration_line_v2(line, kernel)
    character(len=*), intent(in) :: line
    type(shader_kernel_v2), intent(inout) :: kernel
    integer :: i
    integer, save :: binding_slot = 0
    
    
    ! Parse type declaration
    if (allocated(kernel%args)) then
      do i = 1, size(kernel%args)
        ! Check if this argument appears in the declaration line
        block
          integer :: pos, name_len, j
          character(len=512) :: after_coloncolon, var_list
          logical :: found_match
          
          found_match = .false.
          pos = index(line, " :: ")
          if (pos > 0) then
            after_coloncolon = adjustl(line(pos+4:))
            
            ! Check each comma-separated variable in the declaration
            var_list = after_coloncolon
            do while (len_trim(var_list) > 0)
              ! Extract next variable name
              pos = index(var_list, ",")
              if (pos > 0) then
                ! Check this variable
                if (trim(adjustl(var_list(1:pos-1))) == trim(kernel%args(i)%name)) then
                  found_match = .true.
                  exit
                end if
                var_list = adjustl(var_list(pos+1:))
              else
                ! Last variable in the list
                if (trim(adjustl(var_list)) == trim(kernel%args(i)%name)) then
                  found_match = .true.
                end if
                exit
              end if
            end do
          end if
          
          if (.not. found_match) cycle
        end block
          ! Extract type
          if (index(line, "integer(i32)") > 0) then
            kernel%args(i)%type_str = "integer(i32)"
          else if (index(line, "real(sp)") > 0) then
            kernel%args(i)%type_str = "real(sp)"
          else if (index(line, "real(dp)") > 0) then
            kernel%args(i)%type_str = "real(dp)"
          end if
          
          ! Extract intent
          if (index(line, "value") > 0) then
            kernel%args(i)%intent = "value"
            kernel%args(i)%is_scalar = .true.
            kernel%args(i)%binding_slot = -1
          else if (index(line, "intent(out)") > 0) then
            kernel%args(i)%intent = "out"
            kernel%args(i)%binding_slot = binding_slot
            binding_slot = binding_slot + 1
          else if (index(line, "intent(in)") > 0) then
            kernel%args(i)%intent = "in"
            kernel%args(i)%binding_slot = binding_slot
            binding_slot = binding_slot + 1
          else if (index(line, "intent(inout)") > 0) then
            kernel%args(i)%intent = "inout"
            kernel%args(i)%binding_slot = binding_slot
            binding_slot = binding_slot + 1
          end if
      end do
    end if
  end subroutine parse_declaration_line_v2
  
  subroutine organize_parameters(kernel)
    type(shader_kernel_v2), intent(inout) :: kernel
    integer :: i, num_params
    type(kernel_param), allocatable :: temp_params(:)
    
    ! Count scalar parameters
    num_params = 0
    if (allocated(kernel%args)) then
      do i = 1, size(kernel%args)
        if (kernel%args(i)%is_scalar) num_params = num_params + 1
      end do
    end if
    
    if (num_params > 0) then
      allocate(kernel%params(num_params))
      num_params = 0
      
      ! Extract scalar parameters
      if (allocated(kernel%args)) then
        do i = 1, size(kernel%args)
          if (kernel%args(i)%is_scalar) then
            num_params = num_params + 1
            kernel%params(num_params)%name = kernel%args(i)%name
            kernel%params(num_params)%type_str = kernel%args(i)%type_str
            kernel%params(num_params)%param_index = num_params - 1  ! 0-based
          end if
        end do
      end if
    end if
  end subroutine organize_parameters

  function generate_glsl_v2(kernel) result(glsl_source)
    type(shader_kernel_v2), intent(in) :: kernel
    character(len=:), allocatable :: glsl_source
    
    select case(kernel%param_method)
    case(PARAMS_UNIFORM)
      glsl_source = generate_glsl_uniform_method(kernel)
    case(PARAMS_BUFFER)
      glsl_source = generate_glsl_buffer_method(kernel)
    case(PARAMS_INLINE)
      glsl_source = generate_glsl_inline_method(kernel)
    case default
      glsl_source = generate_glsl_buffer_method(kernel)
    end select
  end function generate_glsl_v2
  
  function generate_glsl_uniform_method(kernel) result(glsl_source)
    type(shader_kernel_v2), intent(in) :: kernel
    character(len=:), allocatable :: glsl_source
    character(len=8192) :: buffer
    character(len=1024) :: translated_body
    integer :: i
    
    ! Header
    buffer = "#version 310 es" // NEW_LINE('A')
    write(buffer, '(A,A,I0,A,I0,A,I0,A)') trim(buffer), &
      "layout(local_size_x = ", kernel%local_size_x, &
      ", local_size_y = ", kernel%local_size_y, &
      ", local_size_z = ", kernel%local_size_z, ") in;" // NEW_LINE('A')
    
    ! Uniform declarations for scalar parameters
    if (allocated(kernel%params)) then
      do i = 1, size(kernel%params)
        buffer = trim(buffer) // "uniform " // &
                 trim(fortran_type_to_glsl(kernel%params(i)%type_str)) // &
                 " " // trim(kernel%params(i)%name) // ";" // NEW_LINE('A')
      end do
    end if
    
    ! Buffer bindings for array parameters
    if (allocated(kernel%args)) then
      do i = 1, size(kernel%args)
        if (kernel%args(i)%binding_slot >= 0) then
          buffer = trim(buffer) // generate_buffer_binding_v2(kernel%args(i)) // NEW_LINE('A')
        end if
      end do
    end if
    
    ! Main function
    buffer = trim(buffer) // NEW_LINE('A') // "void main() {" // NEW_LINE('A')
    
    ! Add global invocation index
    if (allocated(kernel%args) .and. size(kernel%args) > 0) then
      buffer = trim(buffer) // "  uint " // trim(kernel%args(1)%name) // &
               " = gl_GlobalInvocationID.x;" // NEW_LINE('A')
    end if
    
    ! Translate body
    translated_body = translate_fortran_body_v2(kernel%body, kernel%args, kernel%params)
    buffer = trim(buffer) // translated_body
    
    buffer = trim(buffer) // "}" // NEW_LINE('A')
    
    glsl_source = trim(buffer)
  end function generate_glsl_uniform_method
  
  function generate_glsl_buffer_method(kernel) result(glsl_source)
    type(shader_kernel_v2), intent(in) :: kernel
    character(len=:), allocatable :: glsl_source
    character(len=8192) :: buffer
    character(len=1024) :: translated_body
    integer :: i
    
    ! Header
    buffer = "#version 310 es" // NEW_LINE('A')
    write(buffer, '(A,A,I0,A,I0,A,I0,A)') trim(buffer), &
      "layout(local_size_x = ", kernel%local_size_x, &
      ", local_size_y = ", kernel%local_size_y, &
      ", local_size_z = ", kernel%local_size_z, ") in;" // NEW_LINE('A')
    
    ! Parameter buffer (if we have scalar params)
    if (allocated(kernel%params) .and. size(kernel%params) > 0) then
      block
        character(len=8) :: binding_str
        write(binding_str, '(I0)') PARAM_BUFFER_BINDING
        buffer = trim(buffer) // &
                 "layout(std430, binding = " // trim(binding_str) // ") readonly buffer ParamBuffer {" // NEW_LINE('A')
      end block
      do i = 1, size(kernel%params)
        buffer = trim(buffer) // "  " // &
                 trim(fortran_type_to_glsl(kernel%params(i)%type_str)) // &
                 " " // trim(kernel%params(i)%name) // ";" // NEW_LINE('A')
      end do
      buffer = trim(buffer) // "} params;" // NEW_LINE('A')
    end if
    
    ! Buffer bindings for array parameters
    if (allocated(kernel%args)) then
      do i = 1, size(kernel%args)
        if (kernel%args(i)%binding_slot >= 0) then
          buffer = trim(buffer) // generate_buffer_binding_v2(kernel%args(i)) // NEW_LINE('A')
        end if
      end do
    end if
    
    ! Main function
    buffer = trim(buffer) // NEW_LINE('A') // "void main() {" // NEW_LINE('A')
    
    ! Add global invocation index
    if (allocated(kernel%args) .and. size(kernel%args) > 0) then
      buffer = trim(buffer) // "  uint " // trim(kernel%args(1)%name) // &
               " = gl_GlobalInvocationID.x;" // NEW_LINE('A')
    end if
    
    ! Translate body (with params. prefix for scalar variables)
    translated_body = translate_fortran_body_buffer_method(kernel%body, kernel%args, kernel%params)
    buffer = trim(buffer) // translated_body
    
    buffer = trim(buffer) // "}" // NEW_LINE('A')
    
    glsl_source = trim(buffer)
  end function generate_glsl_buffer_method
  
  function generate_glsl_inline_method(kernel) result(glsl_source)
    type(shader_kernel_v2), intent(in) :: kernel
    character(len=:), allocatable :: glsl_source
    character(len=8192) :: buffer
    character(len=1024) :: translated_body
    integer :: i
    
    ! For inline method, parameters will be replaced with constants
    ! This requires the actual values at compile time
    ! For now, use placeholders
    
    ! Header
    buffer = "#version 310 es" // NEW_LINE('A')
    write(buffer, '(A,A,I0,A,I0,A,I0,A)') trim(buffer), &
      "layout(local_size_x = ", kernel%local_size_x, &
      ", local_size_y = ", kernel%local_size_y, &
      ", local_size_z = ", kernel%local_size_z, ") in;" // NEW_LINE('A')
    
    ! Inline constants for scalar parameters
    if (allocated(kernel%params)) then
      do i = 1, size(kernel%params)
        buffer = trim(buffer) // "const " // &
                 trim(fortran_type_to_glsl(kernel%params(i)%type_str)) // &
                 " " // trim(kernel%params(i)%name) // " = PLACEHOLDER_" // &
                 trim(kernel%params(i)%name) // ";" // NEW_LINE('A')
      end do
    end if
    
    ! Buffer bindings for array parameters
    if (allocated(kernel%args)) then
      do i = 1, size(kernel%args)
        if (kernel%args(i)%binding_slot >= 0) then
          buffer = trim(buffer) // generate_buffer_binding_v2(kernel%args(i)) // NEW_LINE('A')
        end if
      end do
    end if
    
    ! Main function
    buffer = trim(buffer) // NEW_LINE('A') // "void main() {" // NEW_LINE('A')
    
    ! Add global invocation index
    if (allocated(kernel%args) .and. size(kernel%args) > 0) then
      buffer = trim(buffer) // "  uint " // trim(kernel%args(1)%name) // &
               " = gl_GlobalInvocationID.x;" // NEW_LINE('A')
    end if
    
    ! Translate body
    translated_body = translate_fortran_body_v2(kernel%body, kernel%args, kernel%params)
    buffer = trim(buffer) // translated_body
    
    buffer = trim(buffer) // "}" // NEW_LINE('A')
    
    glsl_source = trim(buffer)
  end function generate_glsl_inline_method
  
  function generate_buffer_binding_v2(arg) result(binding)
    type(kernel_arg_v2), intent(in) :: arg
    character(len=256) :: binding
    character(len=32) :: glsl_type, access
    character(len=64) :: safe_name
    
    ! Convert Fortran type to GLSL
    glsl_type = fortran_type_to_glsl(arg%type_str)
    
    ! Determine access qualifier
    select case(arg%intent)
    case("in")
      access = "readonly"
    case("out", "inout")
      access = ""
    end select
    
    ! Rename reserved words
    safe_name = arg%name
    if (trim(arg%name) == "out") safe_name = "out_data"
    
    write(binding, '(A,I0,A,A,A,A,A)') &
      "layout(std430, binding = ", arg%binding_slot, ") ", &
      trim(access), " buffer Buffer", trim(safe_name), &
      " { " // trim(glsl_type) // " " // trim(safe_name) // "[]; };"
  end function generate_buffer_binding_v2
  
  function fortran_type_to_glsl(fortran_type) result(glsl_type)
    character(len=*), intent(in) :: fortran_type
    character(len=32) :: glsl_type
    
    select case(trim(fortran_type))
    case("integer(i32)")
      glsl_type = "uint"
    case("real(sp)")
      glsl_type = "float"
    case("real(dp)")
      glsl_type = "double"
    case default
      glsl_type = "uint"
    end select
  end function fortran_type_to_glsl
  
  function translate_fortran_body_v2(fortran_body, args, params) result(glsl_body)
    character(len=*), intent(in) :: fortran_body
    type(kernel_arg_v2), intent(in) :: args(:)
    type(kernel_param), intent(in), optional :: params(:)
    character(len=1024) :: glsl_body
    character(len=512) :: line, translated_line
    integer :: i, newline_pos
    
    glsl_body = ""
    i = 1
    
    ! Process line by line
    do while (i <= len_trim(fortran_body))
      ! Find next newline
      newline_pos = index(fortran_body(i:), NEW_LINE('A'))
      if (newline_pos > 0) then
        line = fortran_body(i:i+newline_pos-2)
        i = i + newline_pos
      else
        line = fortran_body(i:)
        i = len_trim(fortran_body) + 1
      end if
      
      ! Translate line
      translated_line = translate_fortran_line_v2(line, args, params)
      if (len_trim(translated_line) > 0) then
        glsl_body = trim(glsl_body) // "  " // trim(translated_line) // NEW_LINE('A')
      end if
    end do
  end function translate_fortran_body_v2
  
  function translate_fortran_body_buffer_method(fortran_body, args, params) result(glsl_body)
    character(len=*), intent(in) :: fortran_body
    type(kernel_arg_v2), intent(in) :: args(:)
    type(kernel_param), intent(in) :: params(:)
    character(len=1024) :: glsl_body
    character(len=512) :: line, translated_line
    integer :: i, newline_pos
    
    glsl_body = ""
    i = 1
    
    ! Process line by line
    do while (i <= len_trim(fortran_body))
      ! Find next newline
      newline_pos = index(fortran_body(i:), NEW_LINE('A'))
      if (newline_pos > 0) then
        line = fortran_body(i:i+newline_pos-2)
        i = i + newline_pos
      else
        line = fortran_body(i:)
        i = len_trim(fortran_body) + 1
      end if
      
      ! Translate line (with params. prefix)
      translated_line = translate_fortran_line_buffer_method(line, args, params)
      if (len_trim(translated_line) > 0) then
        glsl_body = trim(glsl_body) // "  " // trim(translated_line) // NEW_LINE('A')
      end if
    end do
  end function translate_fortran_body_buffer_method
  
  function translate_fortran_line_v2(line, args, params) result(translated)
    character(len=*), intent(in) :: line
    type(kernel_arg_v2), intent(in) :: args(:)
    type(kernel_param), intent(in), optional :: params(:)
    character(len=512) :: translated
    character(len=512) :: work_line
    character(len=64) :: safe_name
    integer :: i, j, pos
    
    work_line = adjustl(line)
    translated = work_line
    
    ! Handle hex constants
    pos = index(translated, "int(z'")
    if (pos > 0) then
      i = pos + 6
      do while (i <= len_trim(translated) .and. translated(i:i) /= "'")
        i = i + 1
      end do
      if (i <= len_trim(translated)) then
        translated = translated(1:pos-1) // "0x" // translated(pos+6:i-1) // "u" // &
                    translated(index(translated(i:), ")")+i:)
      end if
    end if
    
    ! Handle real() conversion
    block
      integer :: paren_count, start_pos, end_pos, comma_pos
      character(len=512) :: expr
      
      pos = index(translated, "real(")
      if (pos > 0) then
        start_pos = pos + 5
        paren_count = 1
        i = start_pos
        
        do while (i <= len_trim(translated) .and. paren_count > 0)
          if (translated(i:i) == "(") paren_count = paren_count + 1
          if (translated(i:i) == ")") paren_count = paren_count - 1
          i = i + 1
        end do
        end_pos = i - 1
        
        expr = translated(start_pos:end_pos-1)
        comma_pos = index(expr, ",")
        
        if (comma_pos > 0) then
          expr = trim(expr(1:comma_pos-1))
        end if
        
        translated = translated(1:pos-1) // "float(" // trim(expr) // ")" // &
                    translated(end_pos+1:)
      end if
    end block
    
    ! For array access, add [idx] for all buffer variables
    do i = 1, size(args)
      if (args(i)%binding_slot >= 0) then
        safe_name = args(i)%name
        if (trim(args(i)%name) == "out") safe_name = "out_data"
        
        ! Replace all occurrences
        call replace_array_access(translated, args(i)%name, safe_name, args(1)%name)
      end if
    end do
    
    ! Add semicolon if assignment
    if (index(translated, "=") > 0 .and. index(translated, ";") == 0) then
      translated = trim(translated) // ";"
    end if
  end function translate_fortran_line_v2
  
  function translate_fortran_line_buffer_method(line, args, params) result(translated)
    character(len=*), intent(in) :: line
    type(kernel_arg_v2), intent(in) :: args(:)
    type(kernel_param), intent(in) :: params(:)
    character(len=512) :: translated
    character(len=512) :: work_line
    character(len=64) :: safe_name
    integer :: i, j, pos
    
    work_line = adjustl(line)
    translated = work_line
    
    ! Handle hex constants
    pos = index(translated, "int(z'")
    if (pos > 0) then
      i = pos + 6
      do while (i <= len_trim(translated) .and. translated(i:i) /= "'")
        i = i + 1
      end do
      if (i <= len_trim(translated)) then
        translated = translated(1:pos-1) // "0x" // translated(pos+6:i-1) // "u" // &
                    translated(index(translated(i:), ")")+i:)
      end if
    end if
    
    ! Replace scalar parameter references with params.name
    do i = 1, size(params)
      call replace_param_access(translated, params(i)%name, "params." // trim(params(i)%name))
    end do
    
    ! Handle real() conversion - need to handle the type argument
    block
      integer :: paren_count, start_pos, end_pos, comma_pos
      character(len=512) :: expr, type_arg
      
      pos = index(translated, "real(")
      if (pos > 0) then
        start_pos = pos + 5
        paren_count = 1
        i = start_pos
        
        ! Find the closing paren
        do while (i <= len_trim(translated) .and. paren_count > 0)
          if (translated(i:i) == "(") paren_count = paren_count + 1
          if (translated(i:i) == ")") paren_count = paren_count - 1
          i = i + 1
        end do
        end_pos = i - 1
        
        ! Extract content and look for comma (type specifier)
        expr = translated(start_pos:end_pos-1)
        comma_pos = index(expr, ",")
        
        if (comma_pos > 0) then
          ! Has type specifier, just take the expression part
          expr = trim(expr(1:comma_pos-1))
        end if
        
        ! Replace with float()
        translated = translated(1:pos-1) // "float(" // trim(expr) // ")" // &
                    translated(end_pos+1:)
      end if
    end block
    
    ! For array access, add [idx] for all buffer variables
    do i = 1, size(args)
      if (args(i)%binding_slot >= 0) then
        safe_name = args(i)%name
        if (trim(args(i)%name) == "out") safe_name = "out_data"
        
        ! Replace all occurrences
        call replace_array_access(translated, args(i)%name, safe_name, args(1)%name)
      end if
    end do
    
    ! Add semicolon if assignment
    if (index(translated, "=") > 0 .and. index(translated, ";") == 0) then
      translated = trim(translated) // ";"
    end if
  end function translate_fortran_line_buffer_method
  
  subroutine replace_array_access(str, old_name, new_name, idx_name)
    character(len=*), intent(inout) :: str
    character(len=*), intent(in) :: old_name, new_name, idx_name
    character(len=512) :: temp
    integer :: pos, start_pos, name_len
    
    temp = str
    str = ""
    start_pos = 1
    name_len = len_trim(old_name)
    
    do
      pos = index(temp(start_pos:), trim(old_name))
      if (pos == 0) then
        str = trim(str) // temp(start_pos:)
        exit
      end if
      
      pos = start_pos + pos - 1
      
      ! Check if whole word
      if ((pos == 1 .or. .not. is_identifier_char(temp(pos-1:pos-1))) .and. &
          (pos + name_len > len_trim(temp) .or. &
           .not. is_identifier_char(temp(pos+name_len:pos+name_len)))) then
        str = trim(str) // temp(start_pos:pos-1) // &
              trim(new_name) // "[" // trim(idx_name) // "]"
        start_pos = pos + name_len
      else
        str = trim(str) // temp(start_pos:pos)
        start_pos = pos + 1
      end if
    end do
  end subroutine replace_array_access
  
  subroutine replace_param_access(str, old_name, new_name)
    character(len=*), intent(inout) :: str
    character(len=*), intent(in) :: old_name, new_name
    character(len=512) :: temp
    integer :: pos, start_pos, name_len
    
    temp = str
    str = ""
    start_pos = 1
    name_len = len_trim(old_name)
    
    do
      pos = index(temp(start_pos:), trim(old_name))
      if (pos == 0) then
        str = trim(str) // temp(start_pos:)
        exit
      end if
      
      pos = start_pos + pos - 1
      
      ! Check if whole word
      if ((pos == 1 .or. .not. is_identifier_char(temp(pos-1:pos-1))) .and. &
          (pos + name_len > len_trim(temp) .or. &
           .not. is_identifier_char(temp(pos+name_len:pos+name_len)))) then
        str = trim(str) // temp(start_pos:pos-1) // trim(new_name)
        start_pos = pos + name_len
      else
        str = trim(str) // temp(start_pos:pos)
        start_pos = pos + 1
      end if
    end do
  end subroutine replace_param_access
  
  function is_identifier_char(ch) result(is_id)
    character(len=1), intent(in) :: ch
    logical :: is_id
    
    is_id = (ch >= 'a' .and. ch <= 'z') .or. &
            (ch >= 'A' .and. ch <= 'Z') .or. &
            (ch >= '0' .and. ch <= '9') .or. &
            ch == '_'
  end function is_identifier_char

end module sporkle_shader_parser_v2