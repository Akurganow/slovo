#ifndef CLEANUP_BENCHMARK_FUZZ_H
#define CLEANUP_BENCHMARK_FUZZ_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* RapidFuzz token_sort_ratio, 0...100, over arrays of integer ids. */
double cleanup_benchmark_token_sort_ratio(const uint32_t *a, size_t an, const uint32_t *b, size_t bn);

#ifdef __cplusplus
}
#endif

#endif
