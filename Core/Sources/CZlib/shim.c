#include "CZlib.h"
#include <zlib.h>

int apphub_inflate_raw(const uint8_t *src, size_t src_len,
                       uint8_t *dst, size_t dst_len, size_t *written) {
    z_stream stream;
    stream.zalloc = Z_NULL;
    stream.zfree = Z_NULL;
    stream.opaque = Z_NULL;
    stream.next_in = (Bytef *)src;
    stream.avail_in = (uInt)src_len;
    stream.next_out = dst;
    stream.avail_out = (uInt)dst_len;

    if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) {
        return -1;
    }

    int result = inflate(&stream, Z_FINISH);
    *written = stream.total_out;
    inflateEnd(&stream);

    if (result == Z_STREAM_END) {
        return 0;
    }
    if (result == Z_BUF_ERROR) {
        return -3;
    }
    return -2;
}
