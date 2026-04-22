#import "DPFastScanner.h"

#include <sys/attr.h>
#include <sys/stat.h>
#include <sys/types.h>
// <sys/vnode.h> isn't part of the iOS SDK; define the vnode type constants
// we need inline. These values are stable ABI (xnu vnode.h).
#ifndef VREG
#define VNON  0
#define VREG  1
#define VDIR  2
#define VBLK  3
#define VCHR  4
#define VLNK  5
#define VSOCK 6
#define VFIFO 7
#endif
#ifndef FSOBJ_TYPE_T_DEFINED
typedef uint32_t fsobj_type_t_compat;
#endif
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <errno.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <stdio.h>
#include <dispatch/dispatch.h>

// 256 KiB bulk buffer: fewer syscalls for big directories. Heap-allocated
// so deep recursion doesn't blow the stack.
#define DP_BULK_BUF_SIZE (256 * 1024)

// Bound concurrent directory readers. Beyond ~8 parallel walks, storage
// seek/contention hurts more than parallelism helps.
#define DP_MAX_INFLIGHT 8

// getattrlistbulk options: ask the kernel to keep returning entries even
// when individual per-attr errors occur, instead of dropping the whole
// entry/batch. FSOPT_PACK_INVAL_ATTRS = 0x00000008.
#ifndef FSOPT_PACK_INVAL_ATTRS
#define FSOPT_PACK_INVAL_ATTRS 0x00000008
#endif
#define DP_BULK_OPTS ((uint64_t)FSOPT_PACK_INVAL_ATTRS)

// Layout of each returned entry from getattrlistbulk() when the attrlist
// below is used. Entries are packed and variable-length.
typedef struct entry_s {
    uint32_t         length;
    attribute_set_t  returned;
    uint32_t         err;
    attrreference_t  nameref;
    fsobj_type_t     obj_type;
    off_t            alloc_size;
} __attribute__((packed)) entry_t;

static void build_attrlist(struct attrlist *al) {
    memset(al, 0, sizeof(*al));
    al->bitmapcount = ATTR_BIT_MAP_COUNT;
    al->commonattr  = ATTR_CMN_RETURNED_ATTRS | ATTR_CMN_ERROR
                    | ATTR_CMN_NAME | ATTR_CMN_OBJTYPE;
    al->fileattr    = ATTR_FILE_ALLOCSIZE;
}

// Shared state for recursive parallel walks.
typedef struct scan_ctx_s {
    _Atomic uint64_t    total;
    dispatch_semaphore_t sem;   // bounds concurrent readers
    dispatch_group_t     group; // waits for all dispatched walks
    dispatch_queue_t     queue; // USER_INITIATED global queue
    int                  notsup; // sticky flag (non-atomic; hint only)
} scan_ctx_t;

// Forward decl.
static void scan_dir_shared(const char *path, scan_ctx_t *sctx);

// Core directory walk. Accumulates regular-file sizes into sctx->total
// using atomic relaxed adds. For each child directory, tries to dispatch
// a concurrent walk via the semaphore; if the semaphore is saturated,
// recurses in-thread to keep progress moving without thrashing storage.
static void scan_dir_shared(const char *path, scan_ctx_t *sctx) {
    int fd = open(path, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return;

    struct attrlist al;
    build_attrlist(&al);

    char *buf = (char *)malloc(DP_BULK_BUF_SIZE);
    if (!buf) { close(fd); return; }

    size_t plen = strlen(path);

    for (;;) {
        int n = getattrlistbulk(fd, &al, buf, DP_BULK_BUF_SIZE, DP_BULK_OPTS);
        if (n == 0) break;
        if (n < 0) {
            if (errno == ENOTSUP) sctx->notsup = 1;
            break;
        }

        char *cursor = buf;
        for (int i = 0; i < n; i++) {
            entry_t *e = (entry_t *)cursor;
            uint32_t entry_len = e->length;
            char *next = cursor + entry_len;

            if (e->err) { cursor = next; continue; }

            const char *name = ((const char *)&e->nameref)
                             + e->nameref.attr_dataoffset;
            // Dot-dir skip first — avoids any further work on "." / "..".
            if (name[0] == '.' && (name[1] == '\0'
                || (name[1] == '.' && name[2] == '\0'))) {
                cursor = next;
                continue;
            }

            fsobj_type_t ot = e->obj_type;
            if (ot == VREG) {
                atomic_fetch_add_explicit(&sctx->total,
                                          (uint64_t)e->alloc_size,
                                          memory_order_relaxed);
            } else if (ot == VDIR) {
                size_t nlen = strlen(name);
                if (plen + 1 + nlen + 1 <= PATH_MAX) {
                    char *child = (char *)malloc(plen + 1 + nlen + 1);
                    if (child) {
                        memcpy(child, path, plen);
                        child[plen] = '/';
                        memcpy(child + plen + 1, name, nlen);
                        child[plen + 1 + nlen] = '\0';

                        // Try to parallelize; only if under inflight cap.
                        if (dispatch_semaphore_wait(sctx->sem, DISPATCH_TIME_NOW) == 0) {
                            dispatch_group_async(sctx->group, sctx->queue, ^{
                                scan_dir_shared(child, sctx);
                                dispatch_semaphore_signal(sctx->sem);
                                free(child);
                            });
                        } else {
                            // Saturated: keep walking on this thread.
                            scan_dir_shared(child, sctx);
                            free(child);
                        }
                    }
                }
            }
            // VLNK and other types are skipped.

            cursor = next;
        }
    }

    free(buf);
    close(fd);
}

unsigned long long DPFastDirectorySize(const char *path) {
    if (!path || !*path) return 0;

    // Quick probe on the root so we can return 0 (fallback) on ENOTSUP or
    // open failure without spinning up the shared scan context.
    {
        int pfd = open(path, O_RDONLY | O_NOFOLLOW);
        if (pfd < 0) return 0;
        struct attrlist pal;
        build_attrlist(&pal);
        char probe[4096];
        int pn = getattrlistbulk(pfd, &pal, probe, sizeof(probe), DP_BULK_OPTS);
        if (pn < 0 && errno == ENOTSUP) { close(pfd); return 0; }
        close(pfd);
    }

    scan_ctx_t sctx;
    atomic_init(&sctx.total, (uint64_t)0);
    sctx.sem    = dispatch_semaphore_create(DP_MAX_INFLIGHT);
    sctx.group  = dispatch_group_create();
    sctx.queue  = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    sctx.notsup = 0;

    scan_dir_shared(path, &sctx);
    dispatch_group_wait(sctx.group, DISPATCH_TIME_FOREVER);

    if (sctx.notsup) return 0;
    return (unsigned long long)atomic_load_explicit(&sctx.total,
                                                    memory_order_relaxed);
}

// --- Variant with per-directory callback and exclusion list. ---

static int path_excluded(const char *path, const char * const *excluded) {
    if (!excluded) return 0;
    for (size_t i = 0; excluded[i]; i++) {
        if (strcmp(path, excluded[i]) == 0) return 1;
    }
    return 0;
}

static int scan_dir_bulk_cb(const char *path,
                            uint64_t *out_total,
                            uint64_t *out_items,
                            const char * const *excluded,
                            DPFastDirectoryCallback cb,
                            void *ctx,
                            int *out_notsup) {
    int fd = open(path, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return -1;

    struct attrlist al;
    build_attrlist(&al);

    char *buf = (char *)malloc(DP_BULK_BUF_SIZE);
    if (!buf) { close(fd); return -1; }

    uint64_t total = 0;
    uint64_t items = 0;
    size_t plen = strlen(path);

    for (;;) {
        int n = getattrlistbulk(fd, &al, buf, DP_BULK_BUF_SIZE, DP_BULK_OPTS);
        if (n == 0) break;
        if (n < 0) {
            if (errno == ENOTSUP) {
                if (out_notsup) *out_notsup = 1;
                free(buf); close(fd); return 0;
            }
            break;
        }
        char *cursor = buf;
        for (int i = 0; i < n; i++) {
            entry_t *e = (entry_t *)cursor;
            char *next = cursor + e->length;
            if (e->err) { cursor = next; continue; }

            const char *name = ((const char *)&e->nameref)
                             + e->nameref.attr_dataoffset;
            // Dot-dir skip first.
            if (name[0] == '.' && (name[1] == '\0'
                || (name[1] == '.' && name[2] == '\0'))) {
                cursor = next;
                continue;
            }

            fsobj_type_t ot = e->obj_type;
            size_t nlen = strlen(name);
            if (plen + 1 + nlen + 1 <= PATH_MAX) {
                char *child = (char *)malloc(plen + 1 + nlen + 1);
                if (child) {
                    memcpy(child, path, plen);
                    child[plen] = '/';
                    memcpy(child + plen + 1, name, nlen);
                    child[plen + 1 + nlen] = '\0';
                    if (!path_excluded(child, excluded)) {
                        if (ot == VREG) {
                            total += (uint64_t)e->alloc_size;
                            items++;
                        } else if (ot == VDIR) {
                            uint64_t sub = 0, sub_items = 0;
                            int sub_ns = 0;
                            scan_dir_bulk_cb(child, &sub, &sub_items,
                                             excluded, cb, ctx, &sub_ns);
                            total += sub;
                            items += sub_items + 1;
                        }
                    }
                    free(child);
                }
            }
            cursor = next;
        }
    }

    free(buf);
    close(fd);
    if (cb) cb(path, total, items, ctx);
    if (out_total) *out_total = total;
    if (out_items) *out_items = items;
    return 1;
}

unsigned long long DPFastDirectorySizeWithCallback(const char *path,
                                                   const char * const *excluded,
                                                   DPFastDirectoryCallback cb,
                                                   void *ctx) {
    if (!path || !*path) return 0;
    if (path_excluded(path, excluded)) return 0;
    uint64_t total = 0, items = 0;
    int notsup = 0;
    scan_dir_bulk_cb(path, &total, &items, excluded, cb, ctx, &notsup);
    if (notsup) return 0;
    return (unsigned long long)total;
}
