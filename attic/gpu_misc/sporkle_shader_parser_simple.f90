module sporkle_shader_parser_simple
  ! Simplified parser that reads the entire kernel at once
  use kinds
  use iso_c_binding
  implicit none
  private
  
  public :: parse_kernel_simple, print_kernel_info
  public :: shader_kernel_simple
  
  type :: shader_kernel_simple
    character(len=256) :: name = ""
    character(len=4096) :: body = ""
    integer :: num_args = 0
    character(len=64), allocatable :: arg_names(:)
    character(len=32), allocatable :: arg_types(:)
    character(len=16), allocatable :: arg_intents(:)
    logical, allocatable :: is_scalar(:)
  end type
  
contains

  function parse_kernel_simple(filename, kernel_name) result(kernel)
    character(len=*), intent(in) :: filename, kernel_name
    type(shader_kernel_simple) :: kernel
    character(len=512) :: line
    character(len=8192) :: kernel_text
    integer :: unit, iostat, i, kernel_start, kernel_end
    logical :: in_kernel, found_body
    
    kernel%name = kernel_name
    kernel_text = ""
    in_kernel = .false.
    found_body = .false.
    
    open(newunit=unit, file=filename, status='old', action='read', iostat=iostat)
    if (iostat /= 0) then
      print *, "Error opening file: ", filename
      return
    end if
    
    ! Read the entire kernel into a string
    do
      read(unit, '(A)', iostat=iostat) line
      if (iostat /= 0) exit
      
      ! Look for kernel start
      if (index(line, "subroutine " // trim(kernel_name)) > 0) then
        in_kernel = .true.
      end if
      
      if (in_kernel) then
        kernel_text = trim(kernel_text) // trim(line) // NEW_LINE('A')
        if (index(line, "end subroutine") > 0) exit
      end if
    end do
    
    close(unit)
    
    ! Now parse the collected kernel text
    call parse_kernel_text(kernel_text, kernel)
    
  end function parse_kernel_simple
  
  subroutine parse_kernel_text(text, kernel)
    character(len=*), intent(in) :: text
    type(shader_kernel_simple), intent(inout) :: kernel
    character(len=512) :: line
    integer :: i, j, pos, newline_pos
    logical :: found_body
    
    i = 1
    found_body = .false.
    
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
      
      ! Parse subroutine signature
      if (index(line, "subroutine") > 0) then
        call parse_signature(line, kernel)
      
      ! Parse declarations
      else if (index(line, "::") > 0) then
        call parse_declaration(line, kernel)
      
      ! Collect body (skip empty lines, comments, use statements)
      else if (found_body .or. &
               (len_trim(line) > 0 .and. &
                index(line, "use ") == 0 .and. &
                index(line, "!") == 0 .and. &
                index(line, "end subroutine") == 0)) then
        found_body = .true.
        if (index(line, "end subroutine") == 0) then
          kernel%body = trim(kernel%body) // trim(adjustl(line)) // NEW_LINE('A')
        end if
      end if
    end do
  end subroutine parse_kernel_text
  
  subroutine parse_signature(line, kernel)
    character(len=*), intent(in) :: line
    type(shader_kernel_simple), intent(inout) :: kernel
    character(len=512) :: args_str
    integer :: paren_start, paren_end, i, comma_count
    
    ! Extract arguments between parentheses
    paren_start = index(line, "(")
    paren_end = index(line, ")")
    
    if (paren_start > 0 .and. paren_end > paren_start) then
      args_str = line(paren_start+1:paren_end-1)
      
      ! Count arguments
      comma_count = 0
      do i = 1, len_trim(args_str)
        if (args_str(i:i) == ',') comma_count = comma_count + 1
      end do
      kernel%num_args = comma_count + 1
      
      ! Allocate arrays
      allocate(kernel%arg_names(kernel%num_args))
      allocate(kernel%arg_types(kernel%num_args))
      allocate(kernel%arg_intents(kernel%num_args))
      allocate(kernel%is_scalar(kernel%num_args))
      
      ! Initialize
      kernel%arg_types = "unknown"
      kernel%arg_intents = "unknown"
      kernel%is_scalar = .false.
      
      ! Parse argument names
      call parse_arg_names(args_str, kernel%arg_names)
    end if
  end subroutine parse_signature
  
  subroutine parse_arg_names(args_str, names)
    character(len=*), intent(in) :: args_str
    character(len=64), intent(out) :: names(:)
    character(len=512) :: work_str
    integer :: i, comma_pos
    
    work_str = adjustl(args_str)
    do i = 1, size(names)
      comma_pos = index(work_str, ",")
      if (comma_pos > 0) then
        names(i) = adjustl(work_str(1:comma_pos-1))
        work_str = adjustl(work_str(comma_pos+1:))
      else
        names(i) = adjustl(work_str)
      end if
    end do
  end subroutine parse_arg_names
  
  subroutine parse_declaration(line, kernel)
    character(len=*), intent(in) :: line
    type(shader_kernel_simple), intent(inout) :: kernel
    character(len=64) :: var_name
    integer :: i, double_colon_pos
    
    ! Extract variable name after ::
    double_colon_pos = index(line, "::")
    if (double_colon_pos > 0) then
      var_name = adjustl(line(double_colon_pos+2:))
      
      ! Find matching argument
      do i = 1, kernel%num_args
        if (trim(kernel%arg_names(i)) == trim(var_name)) then
          ! Extract type
          if (index(line, "integer(i32)") > 0) then
            kernel%arg_types(i) = "integer(i32)"
          else if (index(line, "real(sp)") > 0) then
            kernel%arg_types(i) = "real(sp)"
          else if (index(line, "real(dp)") > 0) then
            kernel%arg_types(i) = "real(dp)"
          end if
          
          ! Extract intent
          if (index(line, "value") > 0) then
            kernel%arg_intents(i) = "value"
            kernel%is_scalar(i) = .true.
          else if (index(line, "intent(out)") > 0) then
            kernel%arg_intents(i) = "out"
          else if (index(line, "intent(in)") > 0) then
            kernel%arg_intents(i) = "in"
          else if (index(line, "intent(inout)") > 0) then
            kernel%arg_intents(i) = "inout"
          end if
          exit
        end if
      end do
    end if
  end subroutine parse_declaration
  
  subroutine print_kernel_info(kernel)
    type(shader_kernel_simple), intent(in) :: kernel
    integer :: i
    
    print *, "Kernel: ", trim(kernel%name)
    print *, "Arguments: ", kernel%num_args
    do i = 1, kernel%num_args
      print *, "  ", i, ": ", trim(kernel%arg_names(i)), &
               " type=", trim(kernel%arg_types(i)), &
               " intent=", trim(kernel%arg_intents(i)), &
               " scalar=", kernel%is_scalar(i)
    end do
    print *, "Body:"
    print *, trim(kernel%body)
  end subroutine print_kernel_info

end module sporkle_shader_parser_simple