/* SPDX-License-Identifier: Apache-2.0 */
#ifndef JSON_HELPERS_H
#define JSON_HELPERS_H
#include <string.h>
#include <stdint.h>
#include "core_json.h"
static inline int json_string(const char *b,size_t n,const char *q,char *out,size_t cap) {
    const char *v;size_t len;JSONTypes_t t;
    if(JSON_SearchConst(b,n,q,strlen(q),&v,&len,&t)!=JSONSuccess||t!=JSONString||len>=cap)return -1;
    for(size_t i=0;i<len;i++)if(v[i]=='\\'||(unsigned char)v[i]<32||(unsigned char)v[i]>126)return -1;
    memcpy(out,v,len);out[len]=0;return 0;
}
static inline int json_u32(const char *b,size_t n,const char *q,uint32_t *out) {
    const char *v;size_t len;JSONTypes_t t;uint32_t r=0;
    if(JSON_SearchConst(b,n,q,strlen(q),&v,&len,&t)!=JSONSuccess||t!=JSONNumber||!len)return -1;
    for(size_t i=0;i<len;i++){
        if(v[i]<'0'||v[i]>'9'||r>(UINT32_MAX-(unsigned)(v[i]-'0'))/10)return -1;
        r=r*10+(unsigned)(v[i]-'0');
    }
    *out=r;return 0;
}
static inline int json_true(const char *b,size_t n,const char *q) {
    const char *v;size_t len;JSONTypes_t t;
    return JSON_SearchConst(b,n,q,strlen(q),&v,&len,&t)==JSONSuccess&&t==JSONTrue;
}
#endif
