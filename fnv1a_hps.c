#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <time.h>
#define CHAR_LO   0x61
#define CHAR_HI   0x7A
#define CHARSET_N (CHAR_HI - CHAR_LO + 1)
#define PW_LEN    4
#define  FNV_OFFSET 0x811c9dc5U
#define  FNV_PRIME 0x01000193U
uint32_t fnv1a(const char *s, int len) {
    uint32_t h = FNV_OFFSET;
    for (int i = 0; i < len; i++) {
        h ^= (uint8_t)s[i];
        h *= FNV_PRIME;
    }
    return h;
}
void decode(uint32_t idx, char out[PW_LEN]) {
    for (int i = 0 ; i < PW_LEN; i++) {
        out[i] = CHAR_LO + (idx % CHARSET_N);
        idx /= CHARSET_N;
    }
}
int main () {
    uint32_t target = fnv1a("test", PW_LEN);
    uint32_t max = 1;
    for (int i = 0; i < PW_LEN; i++) max *= CHARSET_N;
    char cand[PW_LEN];
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (uint32_t idx = 0 ; idx < max ; idx ++) {
        decode(idx, cand);
        if (fnv1a(cand,PW_LEN) == target) {
            clock_gettime(CLOCK_MONOTONIC, &t1);
            double ms = (t1.tv_sec - t0.tv_sec)*1000.0 + (t1.tv_nsec - t0.tv_nsec)/1e6;
            printf("CRACKED: '%.4s' at index %u, %u tries, %.3f ms\n",
                   cand, idx, idx+1, ms);
            return 0;
            }
        }
    printf("not found in keyspace\n");
    return 0;
}