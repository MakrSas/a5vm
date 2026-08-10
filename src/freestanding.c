#include <stdarg.h>
#include <stddef.h>

void *memset(void *destination, int value, size_t length) {
    unsigned char *bytes = (unsigned char *)destination;
    size_t index;
    for (index = 0; index < length; ++index) bytes[index] = (unsigned char)value;
    return destination;
}

int vsnprintf(char *buffer, size_t length, const char *format, va_list args) {
    const char message[] = "A5VM fault";
    size_t index;
    (void)format;
    (void)args;
    if (length == 0) return (int)(sizeof(message) - 1);
    for (index = 0; index + 1 < length && index < sizeof(message) - 1; ++index) {
        buffer[index] = message[index];
    }
    buffer[index] = '\0';
    return (int)(sizeof(message) - 1);
}
