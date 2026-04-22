#ifndef DPFastScanner_h
#define DPFastScanner_h

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Sum sizes of all regular files under `path` (excluding symlinks).
// Uses getattrlistbulk(2) + parallel top-level subdir walks. Thread-safe.
// Returns 0 on open error or when the filesystem does not support
// getattrlistbulk (ENOTSUP); callers may fall back to another walker.
unsigned long long DPFastDirectorySize(const char *path);

// Callback invoked for every directory visited (including `path` itself),
// with the cumulative byte total of regular files in that subtree.
// `excluded` is a NULL-terminated list of absolute paths to skip (used to
// keep volumes from descending into other mount points); may be NULL.
// Returns total bytes under `path`. Returns 0 on ENOTSUP.
typedef void (*DPFastDirectoryCallback)(const char *path,
                                        unsigned long long totalBytes,
                                        unsigned long long totalItems,
                                        void *ctx);
unsigned long long DPFastDirectorySizeWithCallback(const char *path,
                                                   const char * const *excluded,
                                                   DPFastDirectoryCallback cb,
                                                   void *ctx);

#ifdef __cplusplus
}
#endif

#endif /* DPFastScanner_h */
