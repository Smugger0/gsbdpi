#ifndef _GETLINE_H
#define _GETLINE_H

#include <stdio.h>
#ifdef _MSC_VER
#include <BaseTsd.h>
typedef SSIZE_T ssize_t;
#else
#include <sys/types.h>
#endif

#if !HAVE_GETDELIM
ssize_t	getdelim(char **, size_t *, int, FILE *);
#endif

#if !HAVE_GETLINE
ssize_t	getline(char **, size_t *, FILE *);
#endif

#endif
