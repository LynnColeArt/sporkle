module sporkle_shader_parser
  use kinds
  use iso_c_binding
  implicit none
  private
  
  public :: shader_kernel, kernel_arg
  public :: parse_fortran_kernel, generate_glsl
  
  type :: kernel_arg
    character(len=64) :: name = ""
    character(len=32) :: type_str = ""    ! "integer(i32)", "real(sp)", etc
    character(len=16) :: intent = ""      ! "in", "out", "inout", "value"
    integer :: binding_slot = -1
  end type kernel_arg
  
  type :: shader_kernel
    character(len=256) :: name = ""
    integer :: local_size_x = 64
    integer :: local_size_y = 1
    integer :: local_size_z = 1
    integer :: num_inputs = 0
    integer :: num_outputs = 0
    character(len=4096) :: body = ""
    type(kernel_arg), allocatable :: args(:)
  end type shader_kernel

contains

  function parse_fortran_kernel(filename, kernel_name) result(kernel)
    character(len=*), intent(in) :: filename, kernel_name
    type(shader_kernel) :: kernel
    character(len=512) :: line
    logical :: in_kernel = .false.
    logical :: found_subroutine = .false.
    integer :: unit, iostat
    
    kernel%name = kernel_name
    
    open(newunit=unit, file=filename, status='old', action='read', iostat=iostat)
    if (iostat /= 0) then
      print *, "Error opening file: ", filename
      return
    end if
    
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
      if (in_kernel .and. .not. found_subroutine) then
        if (index(line, "subroutine") > 0 .and. index(line, trim(kernel_name)) > 0) then
          ! print *, "Found subroutine line: ", trim(line)
          call parse_subroutine_signature(unit, line, kernel)
          found_subroutine = .true.
        end if
      end if
      
      ! Collect body (skip the subroutine line itself)
      if (in_kernel .and. found_subroutine) then
        ! Skip empty lines, declarations, and use statements
        if (len_trim(line) > 0 .and. &
            index(line, "subroutine") == 0 .and. &
            index(line, "use ") == 0 .and. &
            index(line, "integer") == 0 .and. &
            index(line, "real") == 0 .and. &
            index(line, "logical") == 0 .and. &
            index(line, "character") == 0 .and. &
            index(line, "type(") == 0) then
          kernel%body = trim(kernel%body) // trim(adjustl(line)) // NEW_LINE('A')
        end if
        if (index(line, "end subroutine") > 0) exit
      end if
    end do
    
    close(unit)
  end function parse_fortran_kernel

  subroutine parse_kernel_annotation(line, kernel)
    character(len=*), intent(in) :: line
    type(shader_kernel), intent(inout) :: kernel
    integer :: start_pos, end_pos, eq_pos, comma_pos
    character(len=64) :: param_str, value
    
    ! Find parentheses
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
  end subroutine parse_kernel_annotation

  subroutine parse_subroutine_signature(unit, first_line, kernel)
    integer, intent(in) :: unit
    character(len=*), intent(in) :: first_line
    type(shader_kernel), intent(inout) :: kernel
    character(len=512) :: line, signature
    character(len=64), allocatable :: arg_names(:)
    integer :: paren_start, paren_end, num_args, i, iostat
    
    ! Start with first line
    signature = first_line
    
    ! Check if we need to read more lines (multi-line signature)
    if (index(signature, ")") == 0) then
      ! Read until we find closing paren
      do
        read(unit, '(A)', iostat=iostat) line
        if (iostat /= 0) exit
        signature = trim(signature) // " " // trim(adjustl(line))
        if (index(line, ")") > 0) exit
      end do
    end if
    
    ! Extract argument list
    paren_start = index(signature, "(")
    paren_end = index(signature, ")")
    
    if (paren_start > 0 .and. paren_end > paren_start) then
      call parse_argument_list(signature(paren_start+1:paren_end-1), arg_names, num_args)
      
      ! Allocate args array
      if (allocated(kernel%args)) deallocate(kernel%args)
      allocate(kernel%args(num_args))
      
      ! Set arg names
      do i = 1, num_args
        kernel%args(i)%name = arg_names(i)
      end do
      
      ! Now parse variable declarations to get types
      ! print *, "Parsing variable declarations for ", num_args, " args"
      call parse_variable_declarations(unit, kernel)
    end if
  end subroutine parse_subroutine_signature

  subroutine parse_argument_list(arg_string, arg_names, num_args)
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
  end subroutine parse_argument_list

  subroutine parse_variable_declarations(unit, kernel)
    integer, intent(in) :: unit
    type(shader_kernel), intent(inout) :: kernel
    character(len=512) :: line
    integer :: iostat, i, binding_slot
    
    binding_slot = 0
    
    ! Read through declarations
    do
      read(unit, '(A)', iostat=iostat) line
      if (iostat /= 0) exit
      ! print *, "Reading declaration line: '", trim(line), "'"
      
      ! Skip use statements and blank lines
      if (index(line, "use ") > 0 .or. len_trim(line) == 0) then
        cycle
      end if
      
      ! Stop at first non-declaration line
      if (index(line, "integer") == 0 .and. index(line, "real") == 0 .and. &
          index(line, "logical") == 0) then
        ! Backspace so we don't lose this line
        backspace(unit)
        exit
      end if
      
      ! Parse type declaration
      do i = 1, size(kernel%args)
        ! Check if this line declares this specific argument
        ! Need to be careful - "i" can appear in "integer" or "intent"
        if (index(line, " :: " // trim(kernel%args(i)%name)) > 0) then
          ! Extract type
          if (index(line, "integer(i32)") > 0) then
            kernel%args(i)%type_str = "integer(i32)"
          else if (index(line, "real(sp)") > 0) then
            kernel%args(i)%type_str = "real(sp)"
          else if (index(line, "real(dp)") > 0) then
            kernel%args(i)%type_str = "real(dp)"
          end if
          
          ! Extract intent - check value first since it's mutually exclusive
          if (index(line, "value") > 0) then
            ! print *, "  Found VALUE for arg ", trim(kernel%args(i)%name)
            kernel%args(i)%intent = "value"
            kernel%args(i)%binding_slot = -1  ! value arguments don't get buffer bindings
          else if (index(line, "intent(out)") > 0) then
            ! print *, "  Found INTENT(OUT) for arg ", trim(kernel%args(i)%name)
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
        end if
      end do
    end do
  end subroutine parse_variable_declarations

  function generate_glsl(kernel) result(glsl_source)
    type(shader_kernel), intent(in) :: kernel
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
    
    ! Buffer bindings
    do i = 1, size(kernel%args)
      if (kernel%args(i)%binding_slot >= 0) then
        buffer = trim(buffer) // generate_buffer_binding(kernel%args(i)) // NEW_LINE('A')
      end if
    end do
    
    ! Main function
    buffer = trim(buffer) // NEW_LINE('A') // "void main() {" // NEW_LINE('A')
    
    ! Add global invocation index (always use first arg name)
    if (size(kernel%args) > 0) then
      buffer = trim(buffer) // "  uint " // trim(kernel%args(1)%name) // &
               " = gl_GlobalInvocationID.x;" // NEW_LINE('A')
      ! Add bounds check - we'll skip it for now since length() isn't available in GLES 3.1
      ! buffer = trim(buffer) // "  if (" // trim(kernel%args(1)%name) // &
      !          " >= out_data.length()) return;" // NEW_LINE('A')
    end if
    
    ! Translate body
    translated_body = translate_fortran_body(kernel%body, kernel%args)
    buffer = trim(buffer) // translated_body
    
    buffer = trim(buffer) // "}" // NEW_LINE('A')
    
    glsl_source = trim(buffer)
  end function generate_glsl

  function generate_buffer_binding(arg) result(binding)
    type(kernel_arg), intent(in) :: arg
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
  end function generate_buffer_binding

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
      glsl_type = "uint"  ! default
    end select
  end function fortran_type_to_glsl

  function translate_fortran_body(fortran_body, args) result(glsl_body)
    character(len=*), intent(in) :: fortran_body
    type(kernel_arg), intent(in) :: args(:)
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
      translated_line = translate_fortran_line(line, args)
      if (len_trim(translated_line) > 0) then
        glsl_body = trim(glsl_body) // "  " // trim(translated_line) // NEW_LINE('A')
      end if
    end do
  end function translate_fortran_body

  function translate_fortran_line(line, args) result(translated)
    character(len=*), intent(in) :: line
    type(kernel_arg), intent(in) :: args(:)
    character(len=512) :: translated
    character(len=512) :: work_line
    character(len=64) :: safe_name
    integer :: i, j, pos
    
    work_line = adjustl(line)
    translated = work_line
    
    ! Debug
    ! print *, "Translating line: '", trim(work_line), "'"
    
    ! Simple translations
    ! Handle hex constants
    pos = index(translated, "int(z'")
    if (pos > 0) then
      ! Extract hex value and convert
      i = pos + 6
      do while (i <= len_trim(translated) .and. translated(i:i) /= "'")
        i = i + 1
      end do
      if (i <= len_trim(translated)) then
        ! Replace int(z'DEADBEEF', int32) with 0xDEADBEEFu
        translated = translated(1:pos-1) // "0x" // translated(pos+6:i-1) // "u" // &
                    translated(index(translated(i:), ")")+i:)
      end if
    end if
    
    ! For array access, need to add [i] for all buffer variables
    do i = 1, size(args)
      if (args(i)%binding_slot >= 0) then
        ! Use safe name for reserved words
        safe_name = args(i)%name
        if (trim(args(i)%name) == "out") safe_name = "out_data"
        
        ! Replace all occurrences of this variable with array access
        block
          character(len=512) :: temp
          integer :: start_pos, name_len
          
          temp = translated
          translated = ""
          start_pos = 1
          name_len = len_trim(args(i)%name)
          
          do
            pos = index(temp(start_pos:), trim(args(i)%name))
            if (pos == 0) then
              ! No more occurrences, append rest
              translated = trim(translated) // temp(start_pos:)
              exit
            end if
            
            ! Adjust position to full string
            pos = start_pos + pos - 1
            
            ! Check if this is a whole word (not part of another identifier)
            if ((pos == 1 .or. .not. is_identifier_char(temp(pos-1:pos-1))) .and. &
                (pos + name_len > len_trim(temp) .or. &
                 .not. is_identifier_char(temp(pos+name_len:pos+name_len)))) then
              ! Replace with array access
              translated = trim(translated) // temp(start_pos:pos-1) // &
                          trim(safe_name) // "[" // trim(args(1)%name) // "]"
              start_pos = pos + name_len
            else
              ! Not a whole word, keep as is
              translated = trim(translated) // temp(start_pos:pos)
              start_pos = pos + 1
            end if
          end do
        end block
      end if
    end do
    
    ! Add semicolon if assignment
    if (index(translated, "=") > 0 .and. index(translated, ";") == 0) then
      translated = trim(translated) // ";"
    end if
  end function translate_fortran_line
  
  function is_identifier_char(ch) result(is_id)
    character(len=1), intent(in) :: ch
    logical :: is_id
    
    is_id = (ch >= 'a' .and. ch <= 'z') .or. &
            (ch >= 'A' .and. ch <= 'Z') .or. &
            (ch >= '0' .and. ch <= '9') .or. &
            ch == '_'
  end function is_identifier_char

end module sporkle_shader_parser