module sporkle_mesh_types
  use iso_c_binding
  use kinds
  implicit none
  private
  
  ! Using rk32 and rk64 from kinds module
  
  ! Device kinds as string constants
  character(len=*), parameter, public :: &
    KIND_CPU = "cpu", &
    KIND_NVIDIA = "nvidia", &
    KIND_AMD = "amd", &
    KIND_APPLE = "apple", &
    KIND_INTEL = "intel", &
    KIND_IGPU = "igpu", &
    KIND_FPGA = "fpga", &
    KIND_UNKNOWN = "unknown"
  
  ! Enhanced device capabilities for mesh awareness
  type, public :: device_capabilities
    character(len=:), allocatable :: kind        ! device type string
    integer :: cores = 0                         ! CPU cores or GPU SMs
    integer :: sm_count = 0                      ! streaming multiprocessors (GPU)
    integer(i64) :: vram_mb = 0               ! device memory in MB
    logical :: unified_mem = .false.             ! supports unified memory
    logical :: has_metal = .false.              ! Apple Metal runtime available
    logical :: has_neural_engine = .false.      ! Apple Neural Engine or dedicated accelerator
    real(rk64) :: peak_gflops = 0.0_rk64       ! theoretical peak
    real(rk64) :: sustained_gflops = 0.0_rk64   ! measured sustained
    real(rk64) :: mem_bw_gbs = 0.0_rk64        ! memory bandwidth GB/s
    logical :: p2p_direct = .false.              ! can do device->device direct
    logical :: uvm_supported = .false.           ! unified virtual memory
    character(len=:), allocatable :: pci_id      ! for caching profiles
    character(len=:), allocatable :: driver_ver  ! for cache invalidation
  end type device_capabilities
  
  ! Device handle for mesh
  type, public :: device_handle
    integer :: id = -1
    type(device_capabilities) :: caps
    type(c_ptr) :: native = c_null_ptr          ! CUDA/HIP/OpenMP handle
    logical :: healthy = .true.
    real(rk32) :: load = 0.0_rk32               ! current load 0.0-1.0
    integer :: failure_count = 0                 ! for self-healing
  end type device_handle
  
  ! Link metrics between devices
  type, public :: link_metrics
    integer :: src_id = -1
    integer :: dst_id = -1
    real(rk64) :: bw_gbs = 0.0_rk64            ! measured bandwidth
    real(rk64) :: latency_us = 1000000.0_rk64  ! measured latency (default high)
    logical :: direct = .false.                  ! true if P2P, false if staged
    integer :: hops = 1                          ! number of hops (1=direct, 2=via host)
    real(rk32) :: reliability = 1.0_rk32        ! 0.0-1.0 success rate
  end type link_metrics
  
  ! Mesh topology graph
  type, public :: mesh_topology
    type(device_handle), allocatable :: devices(:)
    type(link_metrics), allocatable :: links(:)
    integer :: num_devices = 0
    logical :: profiled = .false.
    real(rk64) :: profile_timestamp = 0.0_rk64
  contains
    procedure :: find_device => mesh_find_device
    procedure :: get_link => mesh_get_link
    procedure :: add_device => mesh_add_device
    procedure :: update_link => mesh_update_link
  end type mesh_topology
  
  ! Schedule choice for work distribution
  type, public :: schedule_choice
    integer, allocatable :: device_ids(:)        ! which devices to use
    integer, allocatable :: shards(:)            ! shard size per device
    real(rk64) :: est_ms = 0.0_rk64            ! estimated runtime
    character(len=:), allocatable :: rationale   ! explanation for introspection
  end type schedule_choice
  
  ! Collective operation types
  integer, parameter, public :: &
    OP_SUM = 1, &
    OP_MAX = 2, &
    OP_MIN = 3, &
    OP_MEAN = 4, &
    OP_PROD = 5
    
contains

  ! Find device by ID in mesh
  function mesh_find_device(self, device_id) result(idx)
    class(mesh_topology), intent(in) :: self
    integer, intent(in) :: device_id
    integer :: idx, i
    
    idx = -1
    do i = 1, self%num_devices
      if (self%devices(i)%id == device_id) then
        idx = i
        exit
      end if
    end do
  end function mesh_find_device
  
  ! Get link metrics between two devices
  function mesh_get_link(self, src_id, dst_id) result(link)
    class(mesh_topology), intent(in) :: self
    integer, intent(in) :: src_id, dst_id
    type(link_metrics) :: link
    integer :: i
    
    ! Initialize with defaults (no connection)
    link%src_id = src_id
    link%dst_id = dst_id
    link%direct = .false.
    link%hops = 999
    
    ! Search for existing link
    do i = 1, size(self%links)
      if (self%links(i)%src_id == src_id .and. &
          self%links(i)%dst_id == dst_id) then
        link = self%links(i)
        exit
      end if
    end do
  end function mesh_get_link
  
  ! Add device to mesh
  subroutine mesh_add_device(self, device)
    class(mesh_topology), intent(inout) :: self
    type(device_handle), intent(in) :: device
    type(device_handle), allocatable :: temp(:)
    
    if (.not. allocated(self%devices)) then
      allocate(self%devices(1))
      self%devices(1) = device
      self%num_devices = 1
    else
      ! Grow array
      allocate(temp(self%num_devices + 1))
      temp(1:self%num_devices) = self%devices
      temp(self%num_devices + 1) = device
      call move_alloc(temp, self%devices)
      self%num_devices = self%num_devices + 1
    end if
  end subroutine mesh_add_device
  
  ! Update or add link metrics
  subroutine mesh_update_link(self, link)
    class(mesh_topology), intent(inout) :: self
    type(link_metrics), intent(in) :: link
    type(link_metrics), allocatable :: temp(:)
    integer :: i
    logical :: found
    
    found = .false.
    
    if (.not. allocated(self%links)) then
      allocate(self%links(1))
      self%links(1) = link
      return
    end if
    
    ! Update existing link
    do i = 1, size(self%links)
      if (self%links(i)%src_id == link%src_id .and. &
          self%links(i)%dst_id == link%dst_id) then
        self%links(i) = link
        found = .true.
        exit
      end if
    end do
    
    ! Add new link if not found
    if (.not. found) then
      allocate(temp(size(self%links) + 1))
      temp(1:size(self%links)) = self%links
      temp(size(self%links) + 1) = link
      call move_alloc(temp, self%links)
    end if
  end subroutine mesh_update_link
  
end module sporkle_mesh_types
