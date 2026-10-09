#ifndef _GOODBYEDPI_H
#define _GOODBYEDPI_H

#define HOST_MAXLEN 253
#define MAX_PACKET_SIZE 9016

#ifdef _MSC_VER
#define __attribute__(x)
#define strdup _strdup
#define strcasecmp _stricmp
#define strncasecmp _strnicmp
#include <BaseTsd.h>
typedef SSIZE_T ssize_t;
#pragma warning(disable: 4996) /* POSIX / unsafe CRT warnings */
#pragma warning(disable: 4244) /* Conversion loss of data */
#pragma warning(disable: 4267) /* size_t to int conversion */
#endif

#ifndef DEBUG
#define debug(...) do {} while (0)
#else
#define debug(...) printf(__VA_ARGS__)
#endif

int main(int argc, char *argv[]);
void deinit_all(void);

#endif
