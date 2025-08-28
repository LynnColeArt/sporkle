module elf_parser
  ! ELF Parser for HSACO Files
  ! ==========================
  ! Parses AMD GPU ELF files to extract .text section
  
  use kinds
  use iso_c_binding
  implicit none
  private
  
  public :: parse_elf_text_section
  
  ! ELF structures (64-bit)
  type, bind(c) :: elf64_ehdr
    integer(i8) :: e_ident(16)      ! ELF identification
    integer(i16) :: e_type          ! Object file type
    integer(i16) :: e_machine       ! Machine type
    integer(i32) :: e_version       ! Object file version
    integer(i64) :: e_entry         ! Entry point address
    integer(i64) :: e_phoff         ! Program header offset
    integer(i64) :: e_shoff         ! Section header offset
    integer(i32) :: e_flags         ! Processor-specific flags
    integer(i16) :: e_ehsize        ! ELF header size
    integer(i16) :: e_phentsize     ! Size of program header entry
    integer(i16) :: e_phnum         ! Number of program header entries
    integer(i16) :: e_shentsize     ! Size of section header entry
    integer(i16) :: e_shnum         ! Number of section header entries
    integer(i16) :: e_shstrndx      ! Section name string table index
  end type elf64_ehdr
  
  type, bind(c) :: elf64_shdr
    integer(i32) :: sh_name         ! Section name (index into string table)
    integer(i32) :: sh_type         ! Section type
    integer(i64) :: sh_flags        ! Section flags
    integer(i64) :: sh_addr         ! Virtual address in memory
    integer(i64) :: sh_offset       ! Offset in file
    integer(i64) :: sh_size         ! Size of section
    integer(i32) :: sh_link         ! Link to other section
    integer(i32) :: sh_info         ! Miscellaneous information
    integer(i64) :: sh_addralign    ! Address alignment boundary
    integer(i64) :: sh_entsize      ! Size of entries, if section has table
  end type elf64_shdr
  
  ! Section types
  integer(i32), parameter :: SHT_PROGBITS = 1
  integer(i32), parameter :: SHT_STRTAB = 3
  integer(i32), parameter :: SHT_NOTE = 7
  
  ! AMD GPU ELF machine type
  integer(i16), parameter :: EM_AMDGPU = 224_i16
  
contains

  function parse_elf_text_section(filename, text_data, text_size) result(success)
    character(len=*), intent(in) :: filename
    integer(i8), allocatable, intent(out) :: text_data(:)
    integer(i64), intent(out) :: text_size
    logical :: success
    
    integer :: unit, iostat, file_size
    integer(i8), allocatable, target :: file_data(:)
    type(elf64_ehdr), pointer :: ehdr
    type(elf64_shdr), pointer :: shdr
    type(elf64_shdr), pointer :: shdr_array(:)
    type(elf64_shdr), pointer :: strtab_hdr
    character(len=:), allocatable :: section_name
    integer :: i
    integer(i64) :: shdr_offset
    integer(i8), pointer :: strtab_data(:)
    integer(i32) :: name_offset
    
    success = .false.
    text_size = 0
    
    ! Open file
    open(newunit=unit, file=trim(filename), access='stream', &
         form='unformatted', status='old', iostat=iostat)
    if (iostat /= 0) then
      print *, "ERROR: Cannot open ELF file: ", trim(filename)
      return
    end if
    
    ! Get file size
    inquire(unit=unit, size=file_size)
    if (file_size < 64) then
      print *, "ERROR: ELF file too small"
      close(unit)
      return
    end if
    
    ! Read entire file
    allocate(file_data(file_size))
    read(unit) file_data
    close(unit)
    
    ! Parse ELF header
    call c_f_pointer(c_loc(file_data(1)), ehdr)
    
    ! Verify ELF magic
    if (ehdr%e_ident(1) /= int(z'7F', i8) .or. &
        ehdr%e_ident(2) /= iachar('E') .or. &
        ehdr%e_ident(3) /= iachar('L') .or. &
        ehdr%e_ident(4) /= iachar('F')) then
      print *, "ERROR: Not an ELF file"
      deallocate(file_data)
      return
    end if
    
    ! Check machine type
    if (ehdr%e_machine /= EM_AMDGPU) then
      print *, "ERROR: Not an AMD GPU ELF file"
      deallocate(file_data)
      return
    end if
    
    print *, "ELF Header:"
    print '(A,I0)', "  Section header offset: ", ehdr%e_shoff
    print '(A,I0)', "  Number of sections: ", ehdr%e_shnum
    print '(A,I0)', "  Section header size: ", ehdr%e_shentsize
    print '(A,I0)', "  String table index: ", ehdr%e_shstrndx
    
    ! Get section headers
    if (ehdr%e_shoff == 0 .or. ehdr%e_shnum == 0) then
      print *, "ERROR: No section headers"
      deallocate(file_data)
      return
    end if
    
    ! Map section header array
    shdr_offset = ehdr%e_shoff + 1  ! Fortran 1-based
    call c_f_pointer(c_loc(file_data(int(shdr_offset))), shdr_array, [ehdr%e_shnum])
    
    ! Get string table
    if (ehdr%e_shstrndx >= ehdr%e_shnum) then
      print *, "ERROR: Invalid string table index"
      deallocate(file_data)
      return
    end if
    
    strtab_hdr => shdr_array(ehdr%e_shstrndx + 1)  ! Fortran 1-based
    call c_f_pointer(c_loc(file_data(int(strtab_hdr%sh_offset + 1))), &
                     strtab_data, [strtab_hdr%sh_size])
    
    ! Search for .text section
    print *, ""
    print *, "Sections:"
    do i = 1, ehdr%e_shnum
      shdr => shdr_array(i)
      
      ! Get section name
      name_offset = shdr%sh_name + 1  ! Fortran 1-based
      section_name = get_string(strtab_data, name_offset)
      
      print '(A,I2,A,A,A,Z8,A,I0)', "  [", i-1, "] ", section_name, &
            " type=0x", shdr%sh_type, " size=", shdr%sh_size
      
      ! Check if this is .text
      if (section_name == ".text" .and. shdr%sh_type == SHT_PROGBITS) then
        print *, "    ^^^ Found .text section!"
        
        ! Extract text section data
        text_size = shdr%sh_size
        allocate(text_data(text_size))
        text_data = file_data(int(shdr%sh_offset + 1):int(shdr%sh_offset + text_size))
        success = .true.
      end if
    end do
    
    if (.not. success) then
      print *, ""
      print *, "WARNING: No .text section found"
      print *, "Looking for first PROGBITS section..."
      
      ! Fallback: find first PROGBITS section
      do i = 1, ehdr%e_shnum
        shdr => shdr_array(i)
        if (shdr%sh_type == SHT_PROGBITS .and. shdr%sh_size > 0) then
          name_offset = shdr%sh_name + 1
          section_name = get_string(strtab_data, name_offset)
          print '(A,A)', "  Using section: ", section_name
          
          text_size = shdr%sh_size
          allocate(text_data(text_size))
          text_data = file_data(int(shdr%sh_offset + 1):int(shdr%sh_offset + text_size))
          success = .true.
          exit
        end if
      end do
    end if
    
    deallocate(file_data)
    
    if (success) then
      print *, ""
      print '(A,I0,A)', "Extracted ", text_size, " bytes of code"
      print *, "First 16 bytes:"
      do i = 1, min(16, int(text_size))
        write(*, '(Z2.2,A)', advance='no') text_data(i), " "
      end do
      print *, ""
    end if
    
  end function parse_elf_text_section
  
  function get_string(strtab, offset) result(str)
    integer(i8), intent(in) :: strtab(:)
    integer, intent(in) :: offset
    character(len=:), allocatable :: str
    
    integer :: i, len
    
    ! Find string length
    len = 0
    do i = offset, size(strtab)
      if (strtab(i) == 0) exit
      len = len + 1
    end do
    
    ! Allocate and copy string
    allocate(character(len=len) :: str)
    do i = 1, len
      str(i:i) = achar(strtab(offset + i - 1))
    end do
    
  end function get_string

end module elf_parser