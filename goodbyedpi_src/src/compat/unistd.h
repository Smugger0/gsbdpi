#ifndef _COMPAT_UNISTD_H
#define _COMPAT_UNISTD_H

#include <io.h>
#include <process.h>
#include <windows.h>

#define sleep(sec) Sleep((DWORD)((sec) * 1000))

#endif
