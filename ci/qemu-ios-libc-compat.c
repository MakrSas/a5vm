/*
 * __builtin___clear_cache(start, end), used by tcg/arm/tcg-target.h's
 * flush_icache_range() to make freshly JIT-generated ARM code visible to
 * the instruction cache, lowers to a call to a runtime-provided
 * "__clear_cache" symbol on this armv7-apple-ios9.0/iPhoneOS6.1.sdk
 * combination. Neither libSystem nor an auto-linked compiler-rt archive
 * appears to provide it here (the same "symbol postdates this ancient
 * SDK's stub descriptors" gap as clock_gettime and fdopendir), so
 * provide it directly using Darwin's own long-standing cache-control
 * API instead of guessing which compiler-rt archive to link.
 */
#include <libkern/OSCacheControl.h>
#include <stddef.h>

/*
 * clang recognizes this exact name as a builtin and checks any
 * definition against its expected signature -- void (void *, void *),
 * not char * -- so the parameter types below are load-bearing, not a
 * style choice.
 */
void __clear_cache(void *start, void *end)
{
    sys_icache_invalidate(start, (size_t)((char *)end - (char *)start));
}
