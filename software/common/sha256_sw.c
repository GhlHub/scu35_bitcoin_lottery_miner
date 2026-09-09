#include "sha256_sw.h"

#include <string.h>

static const uint32_t k_sha256[64] = {
    0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U,
    0x3956c25bU, 0x59f111f1U, 0x923f82a4U, 0xab1c5ed5U,
    0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U,
    0x72be5d74U, 0x80deb1feU, 0x9bdc06a7U, 0xc19bf174U,
    0xe49b69c1U, 0xefbe4786U, 0x0fc19dc6U, 0x240ca1ccU,
    0x2de92c6fU, 0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU,
    0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U,
    0xc6e00bf3U, 0xd5a79147U, 0x06ca6351U, 0x14292967U,
    0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU, 0x53380d13U,
    0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U,
    0xa2bfe8a1U, 0xa81a664bU, 0xc24b8b70U, 0xc76c51a3U,
    0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U,
    0x19a4c116U, 0x1e376c08U, 0x2748774cU, 0x34b0bcb5U,
    0x391c0cb3U, 0x4ed8aa4aU, 0x5b9cca4fU, 0x682e6ff3U,
    0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U,
    0x90befffaU, 0xa4506cebU, 0xbef9a3f7U, 0xc67178f2U
};

static uint32_t rotr32(uint32_t x, uint32_t n)
{
    return (x >> n) | (x << (32U - n));
}

static uint32_t load_be32(const uint8_t *p)
{
    return ((uint32_t)p[0] << 24) |
           ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8) |
           ((uint32_t)p[3]);
}

static void store_be32(uint8_t *p, uint32_t x)
{
    p[0] = (uint8_t)(x >> 24);
    p[1] = (uint8_t)(x >> 16);
    p[2] = (uint8_t)(x >> 8);
    p[3] = (uint8_t)x;
}

void sha256_init(sha256_ctx_t *ctx)
{
    ctx->h[0] = 0x6a09e667U;
    ctx->h[1] = 0xbb67ae85U;
    ctx->h[2] = 0x3c6ef372U;
    ctx->h[3] = 0xa54ff53aU;
    ctx->h[4] = 0x510e527fU;
    ctx->h[5] = 0x9b05688cU;
    ctx->h[6] = 0x1f83d9abU;
    ctx->h[7] = 0x5be0cd19U;
    ctx->bit_count = 0;
    ctx->buffer_len = 0;
}

void sha256_compress(uint32_t state[8], const uint8_t block[64])
{
    uint32_t w[64];
    uint32_t a;
    uint32_t b;
    uint32_t c;
    uint32_t d;
    uint32_t e;
    uint32_t f;
    uint32_t g;
    uint32_t h;

    for (uint32_t i = 0; i < 16U; ++i) {
        w[i] = load_be32(&block[i * 4U]);
    }

    for (uint32_t i = 16U; i < 64U; ++i) {
        uint32_t s0 = rotr32(w[i - 15U], 7U) ^ rotr32(w[i - 15U], 18U) ^ (w[i - 15U] >> 3);
        uint32_t s1 = rotr32(w[i - 2U], 17U) ^ rotr32(w[i - 2U], 19U) ^ (w[i - 2U] >> 10);
        w[i] = w[i - 16U] + s0 + w[i - 7U] + s1;
    }

    a = state[0];
    b = state[1];
    c = state[2];
    d = state[3];
    e = state[4];
    f = state[5];
    g = state[6];
    h = state[7];

    for (uint32_t i = 0; i < 64U; ++i) {
        uint32_t s1 = rotr32(e, 6U) ^ rotr32(e, 11U) ^ rotr32(e, 25U);
        uint32_t ch = (e & f) ^ (~e & g);
        uint32_t temp1 = h + s1 + ch + k_sha256[i] + w[i];
        uint32_t s0 = rotr32(a, 2U) ^ rotr32(a, 13U) ^ rotr32(a, 22U);
        uint32_t maj = (a & b) ^ (a & c) ^ (b & c);
        uint32_t temp2 = s0 + maj;

        h = g;
        g = f;
        f = e;
        e = d + temp1;
        d = c;
        c = b;
        b = a;
        a = temp1 + temp2;
    }

    state[0] += a;
    state[1] += b;
    state[2] += c;
    state[3] += d;
    state[4] += e;
    state[5] += f;
    state[6] += g;
    state[7] += h;
}

void sha256_update(sha256_ctx_t *ctx, const uint8_t *data, size_t len)
{
    ctx->bit_count += (uint64_t)len * 8ULL;

    while (len > 0U) {
        size_t room = 64U - ctx->buffer_len;
        size_t take = (len < room) ? len : room;

        memcpy(&ctx->buffer[ctx->buffer_len], data, take);
        ctx->buffer_len += take;
        data += take;
        len -= take;

        if (ctx->buffer_len == 64U) {
            sha256_compress(ctx->h, ctx->buffer);
            ctx->buffer_len = 0;
        }
    }
}

void sha256_final(sha256_ctx_t *ctx, uint8_t digest[32])
{
    uint64_t bit_count = ctx->bit_count;

    ctx->buffer[ctx->buffer_len++] = 0x80U;

    if (ctx->buffer_len > 56U) {
        while (ctx->buffer_len < 64U) {
            ctx->buffer[ctx->buffer_len++] = 0;
        }
        sha256_compress(ctx->h, ctx->buffer);
        ctx->buffer_len = 0;
    }

    while (ctx->buffer_len < 56U) {
        ctx->buffer[ctx->buffer_len++] = 0;
    }

    for (uint32_t i = 0; i < 8U; ++i) {
        ctx->buffer[56U + i] = (uint8_t)(bit_count >> (56U - (i * 8U)));
    }

    sha256_compress(ctx->h, ctx->buffer);

    for (uint32_t i = 0; i < 8U; ++i) {
        store_be32(&digest[i * 4U], ctx->h[i]);
    }
}

void bitcoin_header_midstate(const uint8_t header80[80], uint32_t midstate[8])
{
    sha256_ctx_t ctx;

    sha256_init(&ctx);
    sha256_update(&ctx, header80, 64U);

    for (uint32_t i = 0; i < 8U; ++i) {
        midstate[i] = ctx.h[i];
    }
}

void bitcoin_header_tail_words(const uint8_t header80[80], uint32_t tail[4])
{
    for (uint32_t i = 0; i < 4U; ++i) {
        tail[i] = load_be32(&header80[64U + (i * 4U)]);
    }
}
