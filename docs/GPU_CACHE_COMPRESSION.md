> [!CAUTION] Documentation credibility note
> Quantified performance and benchmark claims in this repository history are in recovery and should not be treated as current production facts until revalidated under the Kronos-first flow.


# GPU Binary Cache Compression

## Overview

Sporkle now includes automatic compression for cached GPU shader binaries, reducing disk usage by 50-75% while maintaining fast load times.

## Features

- **Automatic zlib compression** - Shader binaries are compressed before saving to disk
- **Smart compression levels** - Tuned for optimal balance of size vs speed
- **Backwards compatibility** - Can load both compressed and uncompressed cache files
- **Transparent operation** - No API changes required
- **Fallback support** - Works without zlib (saves uncompressed)

## Performance Impact

### Compression Ratios
- **Shader binaries**: [deferred speedup range] compression typical
- **Compute kernels**: [deferred speedup range] compression typical  
- **Complex shaders**: [deferred speedup range] compression typical

### Timing
- **Compression overhead**: <[deferred latency] for typical shaders
- **Decompression overhead**: <[deferred latency] (faster than disk I/O saved)
- **Net result**: Often faster due to reduced disk I/O

## Usage

The compression is automatic when using the GPU cache:

```fortran
use gpu_binary_cache_compressed

! Initialize (detects zlib availability)
call compression_init()

! Save compressed binary
call save_program_binary_compressed(program_id, "conv2d_256x256", cache_dir)

! Load with automatic decompression
program_id = load_program_binary_compressed("conv2d_256x256", cache_dir)
```

## File Format

Compressed cache files use the `.binz` extension and include a header:

```
[Magic: 'ZLIB'] [Version: 1] [Format] [Uncompressed Size] [Compressed Size] [Data...]
```

## Configuration

Set compression level via environment variable:
```bash
export SPORKLE_COMPRESSION_LEVEL=9  # Max compression (slower)
export SPORKLE_COMPRESSION_LEVEL=1  # Fast compression
export SPORKLE_COMPRESSION_LEVEL=6  # Default (balanced)
```

## Benefits

1. **Disk Space** - 50-75% reduction in cache size
2. **Network** - Faster transfers for distributed caching
3. **Memory** - More shaders fit in OS file cache
4. **Scalability** - Support more shader variants

## Example Statistics

For a typical ML workload with 50 shader variants:
- Uncompressed: 25 MB
- Compressed: 8.5 MB  
- Space saved: 66%
- Load time impact: <[deferred latency] per shader

## Building with Compression

Link with zlib:
```bash
gfortran -o myapp myapp.f90 gpu_binary_cache_compressed.f90 -lz
```

Without zlib, compression is automatically disabled with no errors.