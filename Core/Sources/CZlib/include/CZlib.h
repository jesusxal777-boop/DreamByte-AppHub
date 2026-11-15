#ifndef APPHUB_CZLIB_H
#define APPHUB_CZLIB_H

#include <stddef.h>
#include <stdint.h>

/// Inflates a raw DEFLATE stream (no zlib/gzip header).
/// Returns 0 on success, -1 on initialization failure, -2 on invalid data,
/// -3 when the output buffer is too small.
int apphub_inflate_raw(const uint8_t *src, size_t src_len,
                       uint8_t *dst, size_t dst_len, size_t *written);

#endif
