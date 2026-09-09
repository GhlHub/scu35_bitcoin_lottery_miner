#ifndef SHA256_SW_H
#define SHA256_SW_H

#include <stddef.h>
#include <stdint.h>

typedef struct {
    uint32_t h[8];
    uint64_t bit_count;
    uint8_t buffer[64];
    size_t buffer_len;
} sha256_ctx_t;

void sha256_init(sha256_ctx_t *ctx);
void sha256_update(sha256_ctx_t *ctx, const uint8_t *data, size_t len);
void sha256_final(sha256_ctx_t *ctx, uint8_t digest[32]);
void sha256_compress(uint32_t state[8], const uint8_t block[64]);
void bitcoin_header_midstate(const uint8_t header80[80], uint32_t midstate[8]);
void bitcoin_header_tail_words(const uint8_t header80[80], uint32_t tail[4]);

#endif
