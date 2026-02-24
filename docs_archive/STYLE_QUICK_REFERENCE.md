> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# Sporkle Style Quick Reference

## 🎯 The Essentials

```fortran
module sporkle_example
  use iso_fortran_env, only: int32, int64, real32, real64
  implicit none              ! ALWAYS
  private                   ! Default private
  public :: what_you_export ! Explicit public
```

## 🔤 Naming

| Type | Convention | Example |
|------|------------|---------|
| Modules | snake_case | `sporkle_memory` |
| Types | PascalCase | `DeviceHandle` |
| Functions | snake_case | `allocate_buffer` |
| Variables | snake_case | `device_count` |
| Constants | SCREAMING_SNAKE | `MAX_DEVICES` |

## 💪 Strong Typing

```fortran
! Always specify kinds
integer(int32) :: count
integer(int64) :: size_bytes  
real(real32) :: score
real(real64) :: precise_value

! Type your constants
real(real64), parameter :: PI = 3.14159265359_real64
integer(int64), parameter :: GB = 1024_int64**3
```

## 🎨 Layout

- **Indentation**: 2 spaces (no tabs)
- **Line length**: 100 chars max
- **Operators**: Spaces around = + - * /
- **Commas**: Space after, not before

## ✅ Every Module Needs

1. `implicit none`
2. Explicit access control (`private`/`public`)
3. Typed parameters (no magic numbers)
4. Input validation
5. Error handling

## 🚫 Never Do This

```fortran
! BAD - No implicit typing ever
real :: x, y, z

! BAD - Magic numbers
buffer_size = 1048576

! BAD - Single letter variables (except loop indices)
real(real64) :: a, b, c

! BAD - Abbreviated names
integer :: buf_sz, dev_cnt
```

## ✨ Always Do This

```fortran
! GOOD - Explicit types
real(real64) :: position_x, position_y, position_z

! GOOD - Named constants  
integer(int64), parameter :: BUFFER_SIZE_BYTES = 1024_int64 * 1024_int64

! GOOD - Descriptive names
integer(int32) :: buffer_size, device_count

! GOOD - Initialize types
type :: stats
  integer(int64) :: count = 0
  real(real64) :: mean = 0.0_real64
  logical :: valid = .false.
end type
```

## 📝 Quick Patterns

### Factory Function
```fortran
function create_thing(kind) result(thing)
  integer, intent(in) :: kind
  class(base_thing), allocatable :: thing
  
  select case (kind)
  case (KIND_A); allocate(thing_a :: thing)
  case (KIND_B); allocate(thing_b :: thing)
  end select
end function
```

### Error Handling
```fortran
allocate(buffer(n), stat=ierr)
if (ierr /= 0) error stop "Allocation failed"
```

### Array Operations
```fortran
! Let compiler optimize
result = a * b + c

! Not explicit loops (unless needed)
```

---
**Remember**: Explicit > Implicit, Beautiful > Clever, Clear > Concise