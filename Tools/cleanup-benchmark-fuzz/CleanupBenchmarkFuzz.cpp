#include "CleanupBenchmarkFuzz.h"
#include "rapidfuzz_amalgamated.hpp"

double cleanup_benchmark_token_sort_ratio(const uint32_t *a, size_t an, const uint32_t *b, size_t bn)
{
    return rapidfuzz::fuzz::token_sort_ratio(a, a + an, b, b + bn);
}
