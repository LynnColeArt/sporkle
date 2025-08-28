#ifndef PM4_CONSTANTS_H
#define PM4_CONSTANTS_H

// PM4 Packet Types
#define PM4_NOP                 0x10
#define PM4_CLEAR_STATE         0x12
#define PM4_DISPATCH_DIRECT     0x15
#define PM4_CONTEXT_CONTROL     0x28
#define PM4_ACQUIRE_MEM         0x58
#define PM4_SET_SH_REG          0x76
#define PM4_RELEASE_MEM         0x49

// Register Base Addresses
#define SH_REG_BASE             0x2C00

// Compute Shader Registers (offsets from SH_REG_BASE)
#define COMPUTE_PGM_LO               0x204
#define COMPUTE_PGM_HI               0x205
#define COMPUTE_PGM_RSRC1            0x206
#define COMPUTE_PGM_RSRC2            0x207
#define COMPUTE_NUM_THREAD_X         0x20A
#define COMPUTE_NUM_THREAD_Y         0x20B
#define COMPUTE_NUM_THREAD_Z         0x20C
#define COMPUTE_PGM_RSRC3            0x20D
#define COMPUTE_DISPATCH_INITIATOR   0x215
#define COMPUTE_DIM_X               0x216
#define COMPUTE_DIM_Y               0x217
#define COMPUTE_DIM_Z               0x218
#define COMPUTE_START_X             0x219
#define COMPUTE_START_Y             0x21A
#define COMPUTE_START_Z             0x21B
#define COMPUTE_RESOURCE_LIMITS     0x21E
#define COMPUTE_STATIC_THREAD_MGMT_SE0 0x211
#define COMPUTE_STATIC_THREAD_MGMT_SE1 0x212
#define COMPUTE_STATIC_THREAD_MGMT_SE2 0x213
#define COMPUTE_STATIC_THREAD_MGMT_SE3 0x214

// DISPATCH_DIRECT initiator bits
#define COMPUTE_SHADER_EN       (1 << 0)
#define PARTIAL_TG_EN           (1 << 1)
#define FORCE_START_AT_000      (1 << 2)
#define ORDERED_APPEND_ENBL     (1 << 3)
#define ORDERED_APPEND_MODE     (1 << 4)
#define USE_THREAD_DIMENSIONS   (1 << 5)
#define ORDER_MODE              (1 << 6)
#define SCALAR_L1_INV_VOL       (1 << 10)
#define VECTOR_L1_INV_VOL       (1 << 11)
#define DATA_ATC                (1 << 12)
#define RESTORE                 (1 << 14)

// EOP event types
#define EOP_EVENT_TYPE_CS_PARTIAL_FLUSH  0x04
#define EOP_EVENT_TYPE_CS_VS_PARTIAL_FLUSH 0x05
#define EOP_EVENT_TYPE_CACHE_FLUSH_AND_INV 0x14

#endif // PM4_CONSTANTS_H