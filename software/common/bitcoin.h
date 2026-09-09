/* SPDX-License-Identifier: Apache-2.0 */
#ifndef BITCOIN_H
#define BITCOIN_H
#include <stddef.h>
#include <stdint.h>
int bitcoin_target(const char *difficulty,size_t length,uint32_t target[8]);
int hex_decode(const char *hex,size_t n,uint8_t *out,size_t capacity);
void hex_encode(const uint8_t *bytes,size_t n,char *out);
void sha256d(const uint8_t *bytes,size_t n,uint8_t out[32]);
uint32_t bitcoin_swap32(uint32_t x);
void bitcoin_build_header(const uint8_t version[4], const uint8_t prev[32],
    const uint8_t bits[4], const uint8_t time[4], const uint8_t *coin1,size_t n1,
    const uint8_t *extra1,size_t e1,const uint8_t *extra2,size_t e2,
    const uint8_t *coin2,size_t n2,const uint8_t branches[][32],size_t nb,uint8_t header[80]);
#endif
