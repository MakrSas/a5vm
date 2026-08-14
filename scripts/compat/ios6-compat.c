/*
 * ios6-compat.c — то немногое из рантайма, чего нет ни в libSystem
 * iPhoneOS 6.1, ни в armv7-срезе compiler-rt.
 *
 * Эмулированный TLS (__emutls_get_address) здесь СОЗНАТЕЛЬНО отсутствует:
 * он есть в libclang_rt.ios.a, и своя реализация, пусть и корректная,
 * оказалась заметно дороже на горячем пути (см. build-qemu.sh).
 */

#include <stddef.h>
#include <libkern/OSCacheControl.h>

/*
 * __clear_cache
 *
 * tcg/arm/tcg-target.h вызывает __builtin___clear_cache(), чтобы только что
 * сгенерированный ARM-код стал виден кэшу инструкций — без этого JIT молча
 * исполняет то, что осталось в кэше от прежнего содержимого этих адресов.
 * Билтин компилируется в вызов внешнего символа __clear_cache, которого в
 * armv7-срезе libclang_rt.ios.a не оказалось (в отличие от emutls —
 * проверено линковкой).
 *
 * Сигнатура обязана быть (void *, void *): именно её ожидает clang, при
 * (char *, char *) он ругается на несовпадение с прототипом билтина.
 */
void __clear_cache(void *start, void *end)
{
    if (end > start) {
        sys_icache_invalidate(start, (size_t)((char *)end - (char *)start));
    }
}
