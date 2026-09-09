/* SPDX-License-Identifier: Apache-2.0 */
#include "bitcoin.h"
#include "sha256_sw.h"
#include <string.h>
int hex_decode(const char *s,size_t n,uint8_t *out,size_t cap){
    if(n%2||n/2>cap)return -1;
    for(size_t i=0;i<n;i++){
        char c=s[i];int v=c>='0'&&c<='9'?c-'0':c>='a'&&c<='f'?c-'a'+10:c>='A'&&c<='F'?c-'A'+10:-1;
        if(v<0)return -1;
        if(!(i&1))out[i/2]=(uint8_t)(v<<4);else out[i/2]|=(uint8_t)v;
    }
    return (int)(n/2);
}
void hex_encode(const uint8_t *bytes,size_t n,char *out){
    static const char h[]="0123456789abcdef";
    for(size_t i=0;i<n;i++){out[i*2]=h[bytes[i]>>4];out[i*2+1]=h[bytes[i]&15];}out[2*n]=0;
}
void sha256d(const uint8_t *bytes,size_t n,uint8_t out[32]){
    sha256_ctx_t c;sha256_init(&c);sha256_update(&c,bytes,n);sha256_final(&c,out);
    sha256_init(&c);sha256_update(&c,out,32);sha256_final(&c,out);
}
uint32_t bitcoin_swap32(uint32_t x){return (x<<24)|((x<<8)&0xff0000)|((x>>8)&0xff00)|(x>>24);}
void bitcoin_build_header(const uint8_t version[4],const uint8_t prev[32],
    const uint8_t bits[4],const uint8_t time[4],const uint8_t *coin1,size_t n1,
    const uint8_t *extra1,size_t e1,const uint8_t *extra2,size_t e2,
    const uint8_t *coin2,size_t n2,const uint8_t branches[][32],size_t nb,uint8_t header[80]) {
    sha256_ctx_t ctx;uint8_t root[32],pair[64];
    sha256_init(&ctx);sha256_update(&ctx,coin1,n1);sha256_update(&ctx,extra1,e1);
    sha256_update(&ctx,extra2,e2);sha256_update(&ctx,coin2,n2);sha256_final(&ctx,root);
    sha256_init(&ctx);sha256_update(&ctx,root,32);sha256_final(&ctx,root);
    for(size_t i=0;i<nb;i++){memcpy(pair,root,32);memcpy(pair+32,branches[i],32);sha256d(pair,64,root);}
    for(unsigned i=0;i<4;i++){header[i]=version[3-i];header[68+i]=time[3-i];header[72+i]=bits[3-i];}
    for(unsigned i=0;i<32;i++)header[4+i]=prev[i^3];
    memcpy(header+36,root,32);memset(header+76,0,4);
}
/* Exact decimal difficulty conversion: floor(difficulty-one target / D).
 * No floating point rounding or truncation of fractional difficulty. */
typedef uint32_t big[32];
static int multiply10(big a,unsigned add){
    uint64_t carry=add;
    for(unsigned i=0;i<32;i++){carry+=(uint64_t)a[i]*10;a[i]=(uint32_t)carry;carry>>=32;}
    return carry?-1:0;
}
static int compare(const big a,const big b){
    for(int i=31;i>=0;i--)if(a[i]!=b[i])return a[i]>b[i]?1:-1;
    return 0;
}
static void subtract(big a,const big b){
    uint64_t borrow=0;
    for(unsigned i=0;i<32;i++){uint64_t sub=(uint64_t)b[i]+borrow;uint32_t old=a[i];a[i]-=(uint32_t)sub;borrow=(uint64_t)old<sub;}
}
int bitcoin_target(const char *s,size_t n,uint32_t out[8]){
    big numerator={0},denominator={0},remainder={0};
    size_t p=0;unsigned digits=0;int fractional=0,point=0,exponent=0,negative=0,nonzero=0;
    if(!n||n>80)return -1;
    while(p<n&&s[p]!='e'&&s[p]!='E'){
        char c=s[p++];
        if(c=='.'){if(point||!digits)return -1;point=1;continue;}
        if(c<'0'||c>'9'||++digits>64)return -1;
        if(point)fractional++;
        nonzero|=c!='0';if(multiply10(denominator,(unsigned)(c-'0')))return -1;
    }
    if(!nonzero||(point&&!fractional))return -1;
    if(p<n){
        p++;if(p<n&&(s[p]=='+'||s[p]=='-'))negative=s[p++]=='-';
        if(p==n)return -1;
        while(p<n){char c=s[p++];if(c<'0'||c>'9'||exponent>128)return -1;exponent=exponent*10+c-'0';}
    }
    if(negative)exponent=-exponent;
    exponent-=fractional;
    if(exponent>128||exponent< -128)return -1;
    numerator[6]=0xffff0000;
    for(int i=0;i<exponent;i++)if(multiply10(denominator,0))return -1;
    for(int i=0;i< -exponent;i++)if(multiply10(numerator,0))return -1;
    memset(out,0,8*sizeof(*out));int overflow=0;
    for(int bit=1023;bit>=0;bit--){
        uint32_t carry=(numerator[bit/32]>>(bit%32))&1;
        for(unsigned i=0;i<32;i++){uint32_t next=remainder[i]>>31;remainder[i]=(remainder[i]<<1)|carry;carry=next;}
        if(compare(remainder,denominator)>=0){
            subtract(remainder,denominator);
            if(bit>=256)overflow=1;else out[7-bit/32]|=1U<<(bit%32);
        }
    }
    if(overflow)for(unsigned i=0;i<8;i++)out[i]=UINT32_MAX;
    return 0;
}
