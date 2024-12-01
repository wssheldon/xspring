#ifndef RUNTIME_DARWIN_H
#define RUNTIME_DARWIN_H

#include "xspring.h"
#include <stdbool.h>

unsigned int HashStringJenkinsOneAtATime32BitA(const char* key);
FARPROC GetSymbolAddressH(void* handle, unsigned int symbolNameHash);
void* GetLibraryHandleH(unsigned int libraryNameHash);
bool InitializeDarwinApi(INSTANCE* instance);

#endif
