/* SPDX-License-Identifier: Apache-2.0 */
#include "json_helpers.h"
#include <assert.h>
#include <stdio.h>
int main(void){
    const char *s="{\"id\":2,\"result\":false,\"error\":[1,\"true\"],\"params\":[\"aa\",4,[]]}";
    size_t n=strlen(s);char out[16];uint32_t v;
    assert(JSON_Validate(s,n)==JSONSuccess);
    assert(!json_true(s,n,"result"));
    assert(!json_u32(s,n,"id",&v)&&v==2);
    assert(!json_string(s,n,"params[0]",out,sizeof(out))&&!strcmp(out,"aa"));
    assert(!json_u32(s,n,"params[1]",&v)&&v==4);
    const char *value;size_t length;JSONTypes_t type;
    assert(JSON_SearchConst(s,n,"params[2][0]",12,&value,&length,&type)==JSONNotFound);
    s="{\"id\":4294967296,\"worker\":\"bad\\\"quote\"}";n=strlen(s);
    assert(json_u32(s,n,"id",&v));assert(json_string(s,n,"worker",out,sizeof(out)));
    puts("PASS: typed JSON, array paths, overflow and escaping rejection");
}
