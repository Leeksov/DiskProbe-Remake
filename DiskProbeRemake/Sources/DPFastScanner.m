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
#include <dispatch/dispatch.h>

// Layout of each returned entry from getattrlistbulk() when the attrlist
// below is used. The entries are packed and variable-length: each entry
// starts with a uint32_t total length, then the ATTR_CMN_RETURNED_ATTRS
// bitmap, then each requested attribute in attrlist order.
//
// We request, in this order:
//   ATTR_CMN_RETURNED_ATTRS  (attribute_set_t)
//   ATTR_CMN_ERROR           (uint32_t)
//   ATTR_CMN_NAME            (attrreference_t, followed by inline name bytes)
//   ATTR_CMN_OBJTYPE         (fsobj_type_t == uint32_t)
//   ATTR_FILE_DATALENGTH     (off_t == int64_t)
//
// The attrreference_t for the name has an attr_dataoffset which is relative
// to the attrreference_t itself (i.e. to &entry.nameref).
typedef struct entry_s {
    uint32_t         length;
    attribute_set_t  returned;
    uint32_t         err;
    attrreference_t  nameref;
    fsobj_type_t     obj_type;
    off_t            data_length;
} __attribute__((packed)) entry_t;

static void build_attrlist(struct attrlist *al) {
    memset(al, 0, sizeof(*al));
    al->bitmapcount = ATTR_BIT_MAP_COUNT;
    al->commonattr  = ATTR_CMN_RETURNED_ATTRS | ATTR_CMN_ERROR
                    | ATTR_CMN_NAME | ATTR_CMN_OBJTYPE;
    al->fileattr    = ATTR_FILE_DATALENGTH;
}

// Returns 1 on success, 0 if ENOTSUP was encountered (caller should fall
// back), -1 on other open/read errors (still "success" from the standpoint
// that bytes accumulated so far are valid and we keep going).
static int scan_dir_bulk(const char *path, uint64_t *out_total, int *out_notsup) {
    int fd = open(path, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return -1;

    struct attrlist al;
    build_attrlist(&al);

    // 64 KiB buffer is large enough to return many entries per syscall.
    // Keep it off the stack to avoid blowing up deep recursion stacks.
    char *buf = (char *)malloc(64 * 1024);
    if (!buf) { close(fd); return -1; }

    uint64_t total = 0;
    size_t plen = strlen(path);

    for (;;) {
        int n = getattrlistbulk(fd, &al, buf, 64 * 1024, 0);
        if (n == 0) break;
        if (n < 0) {
            if (errno == ENOTSUP) {
                if (out_notsup) *out_notsup = 1;
                free(buf);
                close(fd);
                return 0;
            }
            break;
        }

        char *cursor = buf;
        for (int i = 0; i < n; i++) {
            entry_t *e = (entry_t *)cursor;
            uint32_t entry_len = e->length;
            char *next = cursor + entry_len;

            if (!e->err) {
                // Name is stored at &e->nameref + attr_dataoffset.
                const char *name = ((const char *)&e->nameref)
                                 + e->nameref.attr_dataoffset;
                // Skip "." and ".." defensively (getattrlistbulk normally
                // omits them, but be safe).
                int skip = 0;
                if (name[0] == '.' && (name[1] == '\0'
                    || (name[1] == '.' && name[2] == '\0'))) {
                    skip = 1;
                }
                if (!skip) {
                    fsobj_type_t ot = e->obj_type;
                    if (ot == VREG) {
                        total += (uint64_t)e->data_length;
                    } else if (ot == VDIR) {
                        // Build child path and recurse.
                        size_t nlen = strlen(name);
                        if (plen + 1 + nlen + 1 <= PATH_MAX) {
                            char *child = (char *)malloc(plen + 1 + nlen + 1);
                            if (child) {
                                memcpy(child, path, plen);
                                child[plen] = '/';
                                memcpy(child + plen + 1, name, nlen);
                                child[plen + 1 + nlen] = '\0';
                                uint64_t sub = 0;
                                int sub_notsup = 0;
                                scan_dir_bulk(child, &sub, &sub_notsup);
                                total += sub;
                                free(child);
                            }
                        }
                    }
                    // VLNK and other types are skipped.
                }
            }

            cursor = next;
        }
    }

    free(buf);
    close(fd);
    if (out_total) *out_total = total;
    return 1;
}

unsigned long long DPFastDirectorySize(const char *path) {
    if (!path || !*path) return 0;

    int fd = open(path, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return 0;

    struct attrlist al;
    build_attrlist(&al);

    uint64_t direct_bytes = 0;

    // Collect first-level subdir paths to dispatch_apply across.
    size_t subdirs_cap = 64;
    size_t subdirs_n = 0;
    char **subdirs = (char **)malloc(subdirs_cap * sizeof(char *));
    if (!subdirs) { close(fd); return 0; }

    char *buf = (char *)malloc(64 * 1024);
    if (!buf) { free(subdirs); close(fd); return 0; }

    size_t plen = strlen(path);
    int notsup = 0;

    for (;;) {
        int n = getattrlistbulk(fd, &al, buf, 64 * 1024, 0);
        if (n == 0) break;
        if (n < 0) {
            if (errno == ENOTSUP) { notsup = 1; }
            break;
        }

        char *cursor = buf;
        for (int i = 0; i < n; i++) {
            entry_t *e = (entry_t *)cursor;
            uint32_t entry_len = e->length;
            char *next = cursor + entry_len;

            if (!e->err) {
                const char *name = ((const char *)&e->nameref)
                                 + e->nameref.attr_dataoffset;
                int skip = 0;
                if (name[0] == '.' && (name[1] == '\0'
                    || (name[1] == '.' && name[2] == '\0'))) {
                    skip = 1;
                }
                if (!skip) {
                    fsobj_type_t ot = e->obj_type;
                    if (ot == VREG) {
                        direct_bytes += (uint64_t)e->data_length;
                    } else if (ot == VDIR) {
                        size_t nlen = strlen(name);
                        if (plen + 1 + nlen + 1 <= PATH_MAX) {
                            char *child = (char *)malloc(plen + 1 + nlen + 1);
                            if (child) {
                                memcpy(child, path, plen);
                                child[plen] = '/';
                                memcpy(child + plen + 1, name, nlen);
                                child[plen + 1 + nlen] = '\0';
                                if (subdirs_n == subdirs_cap) {
                                    size_t nc = subdirs_cap * 2;
                                    char **ns = (char **)realloc(subdirs, nc * sizeof(char *));
                                    if (!ns) { free(child); break; }
                                    subdirs = ns;
                                    subdirs_cap = nc;
                                }
                                subdirs[subdirs_n++] = child;
                            }
                        }
                    }
                }
            }

            cursor = next;
        }
    }

    free(buf);
    close(fd);

    if (notsup) {
        for (size_t i = 0; i < subdirs_n; i++) free(subdirs[i]);
        free(subdirs);
        return 0; // Signal fallback.
    }

    // Parallel walk of first-level subdirs.
    _Atomic uint64_t *sub_bytes_p = (_Atomic uint64_t *)malloc(sizeof(_Atomic uint64_t));
    if (!sub_bytes_p) {
        for (size_t i = 0; i < subdirs_n; i++) free(subdirs[i]);
        free(subdirs);
        return 0;
    }
    atomic_init(sub_bytes_p, 0);
    char **subdirs_c = subdirs;
    if (subdirs_n > 0) {
        dispatch_queue_t q = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
        dispatch_apply(subdirs_n, q, ^(size_t i) {
            uint64_t b = 0;
            int sub_notsup = 0;
            scan_dir_bulk(subdirs_c[i], &b, &sub_notsup);
            atomic_fetch_add_explicit(sub_bytes_p, b, memory_order_relaxed);
        });
    }

    uint64_t total = direct_bytes + atomic_load_explicit(sub_bytes_p, memory_order_relaxed);
    free(sub_bytes_p);

    for (size_t i = 0; i < subdirs_n; i++) free(subdirs[i]);
    free(subdirs);

    return (unsigned long long)total;
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

    char *buf = (char *)malloc(64 * 1024);
    if (!buf) { close(fd); return -1; }

    uint64_t total = 0;
    uint64_t items = 0;
    size_t plen = strlen(path);

    for (;;) {
        int n = getattrlistbulk(fd, &al, buf, 64 * 1024, 0);
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
            if (!e->err) {
                const char *name = ((const char *)&e->nameref)
                                 + e->nameref.attr_dataoffset;
                int skip = 0;
                if (name[0] == '.' && (name[1] == '\0'
                    || (name[1] == '.' && name[2] == '\0'))) skip = 1;
                if (!skip) {
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
                                    total += (uint64_t)e->data_length;
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
