#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <libgen.h>

#define MAX_PATH 1024
typedef void* FARPROC;

unsigned int HashStringJenkinsOneAtATime32BitA(const char* key) {
    size_t len = strlen(key);
    unsigned int hash = 0;
    for(size_t i = 0; i < len; ++i) {
        hash += key[i];
        hash += (hash << 10);
        hash ^= (hash >> 6);
    }
    hash += (hash << 3);
    hash ^= (hash >> 11);
    hash += (hash << 15);
    return hash;
}

#define HASHA(API) (HashStringJenkinsOneAtATime32BitA((char*)API))


/**
 * Resolves a symbol address within a loaded Mach-O binary.
 *
 * Uses the Mach-O binary format's load commands to:
 * 1. Locate __LINKEDIT and __TEXT segments
 * 2. Calculate correct address slides
 * 3. Parse symbol table
 * 4. Match symbol by hash
 *
 * Based on ravynOS implementation of symbol resolution for dynamic linking.
 */
FARPROC GetSymbolAddressH(void* handle, unsigned int symbolNameHash) {
    if (!handle) return NULL;

    // Get Mach-O header and initial load command
    const struct mach_header_64* header = (const struct mach_header_64*)handle;
    const struct load_command* cmd = (struct load_command*)((char*)header + sizeof(struct mach_header_64));

    // Find required segments and symbol table
    const struct segment_command_64* linkedit = NULL;
    const struct segment_command_64* text = NULL;
    struct symtab_command* symtab = NULL;

    // Parse load commands to find needed segments
    for (int i = 0; i < header->ncmds; i++) {
        if (cmd->cmd == LC_SEGMENT_64) {
            const struct segment_command_64* seg = (struct segment_command_64*)cmd;
            if (strcmp(seg->segname, "__LINKEDIT") == 0) linkedit = seg;
            if (strcmp(seg->segname, "__TEXT") == 0) text = seg;
        }
        else if (cmd->cmd == LC_SYMTAB) symtab = (struct symtab_command*)cmd;
        cmd = (const struct load_command*)((char*)cmd + cmd->cmdsize);
    }

    // Calculate correct addresses using segments
    intptr_t slide = (intptr_t)header - text->vmaddr;
    const uintptr_t linkedit_base = (uintptr_t)slide + linkedit->vmaddr - linkedit->fileoff;

    // Get symbol and string tables from linkedit segment
    const struct nlist_64* symtab_addr = (struct nlist_64*)(linkedit_base + symtab->symoff);
    const char* strtab = (char*)(linkedit_base + symtab->stroff);

    // Search for matching symbol
    for (uint32_t i = 0; i < symtab->nsyms; i++) {
        if (symtab_addr[i].n_type & N_STAB) continue;  // Skip debug symbols
        const char* sym_name = strtab + symtab_addr[i].n_un.n_strx;
        if (sym_name && sym_name[0] != '\0') {
            if (HASHA(sym_name) == symbolNameHash) {
                return (FARPROC)(symtab_addr[i].n_value + slide);
            }
        }
    }
    return NULL;
}

/**
 * Locates a loaded library by its name hash.
 * Uses dyld APIs to enumerate loaded images and match against hashed name.
 *
 * Names are converted to uppercase for consistent matching regardless of case.
 * Uses basename to match library name without path components.
 */
void* GetLibraryHandleH(unsigned int libraryNameHash) {
    uint32_t count = _dyld_image_count();

    for (uint32_t i = 0; i < count; i++) {
        const char* fullPath = _dyld_get_image_name(i);
        if (!fullPath) continue;

        // Extract filename from path
        char* path = strdup(fullPath);
        char* name = basename(path);

        // Convert to uppercase for case-insensitive comparison
        char upperName[MAX_PATH];
        size_t j = 0;
        while (name[j] && j < MAX_PATH - 1) {
            upperName[j] = toupper(name[j]);
            j++;
        }
        upperName[j] = '\0';

        unsigned int currentHash = HASHA(upperName);
        if (currentHash == libraryNameHash) {
            free(path);
            return (void*)_dyld_get_image_header(i);
        }
        free(path);
    }
    return NULL;
}
