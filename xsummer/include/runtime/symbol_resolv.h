#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include <dlfcn.h>
#include <libgen.h>
#include <stdlib.h>
#include <stdbool.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach/mach.h>
#include <mach/task.h>
#include <mach-o/dyld_images.h>
#include <mach-o/nlist.h>
#include <objc/message.h>
#include <objc/runtime.h>

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

typedef struct dyld_cache* dyld_cache_t;

static struct {
    const struct dyld_all_image_infos* infos;
    bool initialized;
} dyld_cache = {0};

static bool init_dyld_cache(void) {
    if (dyld_cache.initialized) return true;

    struct task_dyld_info info = {0};
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;

    if (task_info(mach_task_self(), TASK_DYLD_INFO, (task_info_t)&info, &count) == KERN_SUCCESS) {
        dyld_cache.infos = (const struct dyld_all_image_infos*)info.all_image_info_addr;
        dyld_cache.initialized = true;
        return true;
    }
    return false;
}

void* GetLibraryHandleH(unsigned int libraryNameHash) {
    if (!init_dyld_cache() || !dyld_cache.infos) return NULL;

    _Alignas(16) char name_buf[PATH_MAX];
    const struct dyld_image_info* curr_info = dyld_cache.infos->infoArray;
    const uint32_t count = dyld_cache.infos->infoArrayCount;

    for (uint32_t i = 0; i < count; i++, curr_info++) {
        if (!curr_info || !curr_info->imageFilePath) continue;

        const char* base = strrchr(curr_info->imageFilePath, '/');
        if (!base++) continue;

        size_t len = strlen(base);
        if (len >= PATH_MAX) continue;

        for (size_t j = 0; j < len; j++) {
            name_buf[j] = (base[j] >= 'a' && base[j] <= 'z') ?
                          base[j] - 32 : base[j];
        }
        name_buf[len] = '\0';

        if (HASHA(name_buf) == libraryNameHash) {
            return (void*)curr_info->imageLoadAddress;
        }
    }
    return NULL;
}
