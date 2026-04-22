#import "NSData+DPCompression.h"
#import <compression.h>

// We optionally link against libbz2 / libz which ship with iOS.
// If they are unavailable at link time, leave DP_HAVE_BZ2 / DP_HAVE_ZLIB
// undefined and the corresponding methods will return the original data.
#if __has_include(<bzlib.h>)
  #import <bzlib.h>
  #define DP_HAVE_BZ2 1
#endif

#if __has_include(<zlib.h>)
  #import <zlib.h>
  #define DP_HAVE_ZLIB 1
#endif

@implementation NSData (DPCompression)

#pragma mark - BZ2

- (NSData *)BZUnzippedData {
    return [self BZUnzippedData:NULL];
}

- (NSData *)BZUnzippedData:(NSString * _Nullable * _Nullable)error {
#if DP_HAVE_BZ2
    if (![self length] || ![self isBZippedData]) {
        if (error) *error = @"This is not a valid BZ2 compressed file";
        return self;
    }

    bz_stream strm;
    memset(&strm, 0, sizeof(strm));
    strm.next_in  = (char *)[self bytes];
    strm.avail_in = (unsigned int)[self length];

    NSMutableData *buffer = [NSMutableData dataWithLength:1024];
    strm.next_out  = (char *)[buffer mutableBytes];
    strm.avail_out = 1024;

    int rc = BZ2_bzDecompressInit(&strm, 0, 0);
    if (rc != BZ_OK) {
        if (error) *error = [NSString stringWithFormat:@"BZ2 Decompression initialization failed with error code: (%d)", rc];
        return self;
    }

    NSMutableData *output = [NSMutableData data];
    while (1) {
        rc = BZ2_bzDecompress(&strm);
        if (rc < 0) {
            if (error) *error = [NSString stringWithFormat:@"BZ2 Decompression stream failed with error code: (%d)", rc];
            return self;
        }
        [output appendBytes:[buffer bytes] length:(1024 - strm.avail_out)];
        strm.next_out  = (char *)[buffer mutableBytes];
        strm.avail_out = 1024;
        if (rc == BZ_STREAM_END) {
            BZ2_bzDecompressEnd(&strm);
            return output;
        }
    }
#else
    if (error) *error = @"BZ2 support was not compiled in";
    return self;
#endif
}

#pragma mark - GZ

- (NSData *)GZUnzippedData {
    return [self GZUnzippedData:NULL];
}

- (NSData *)GZUnzippedData:(NSString * _Nullable * _Nullable)error {
#if DP_HAVE_ZLIB
    if (![self length] || ![self isGZippedData]) {
        if (error) *error = @"This is not a valid GZ compressed file";
        return self;
    }

    z_stream strm;
    strm.zalloc    = Z_NULL;
    strm.zfree     = Z_NULL;
    strm.opaque    = Z_NULL;
    strm.avail_in  = (unsigned int)[self length];
    strm.next_in   = (Bytef *)[self bytes];
    strm.total_out = 0;
    strm.avail_out = 0;

    int rc = inflateInit2(&strm, 47);
    if (rc != Z_OK) {
        if (error) *error = [NSString stringWithFormat:@"GZ Decompression initialization failed with error code: (%d)", rc];
        return self;
    }

    NSMutableData *output = [NSMutableData dataWithCapacity:(2 * [self length])];
    int status = Z_OK;
    while (status != Z_STREAM_END) {
        if (strm.total_out >= [output length]) {
            [output setLength:([output length] + ([self length] >> 1))];
        }
        strm.next_out  = (Bytef *)[output mutableBytes] + strm.total_out;
        strm.avail_out = (unsigned int)([output length] - strm.total_out);

        status = inflate(&strm, Z_SYNC_FLUSH);
        if (status == Z_STREAM_END) {
            if (inflateEnd(&strm) == Z_OK) {
                [output setLength:strm.total_out];
            }
            return output;
        }
        if (status < 0) {
            if (error) *error = [NSString stringWithFormat:@"GZ Decompression stream failed with error code: (%d)", status];
            return self;
        }
    }
    return output;
#else
    if (error) *error = @"GZ support was not compiled in";
    return self;
#endif
}

#pragma mark - XZ (LZMA via Compression.framework)

- (NSData *)XZUnzippedData {
    return [self XZUnzippedData:NULL];
}

- (NSData *)XZUnzippedData:(NSString * _Nullable * _Nullable)error {
    if (![self length]) {
        if (error) *error = @"This is not a valid LZMA(XZ) compressed file";
        return self;
    }

    uint8_t *dstBuffer = malloc(2048);
    compression_stream stream;
    compression_status rc;

    int initRC = compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_LZMA);
    if (initRC != COMPRESSION_STATUS_OK) {
        if (error) *error = [NSString stringWithFormat:@"LZMA(XZ) Decompression initialization failed with error code: (%d)", initRC];
        free(dstBuffer);
        return self;
    }

    stream.dst_ptr  = dstBuffer;
    stream.dst_size = 2048;
    stream.src_ptr  = (const uint8_t *)[self bytes];
    stream.src_size = [self length];

    NSMutableData *output = [NSMutableData new];
    while (1) {
        rc = compression_stream_process(&stream, 0);
        if (rc != COMPRESSION_STATUS_OK) break;
        if (stream.dst_size == 0) {
            [output appendBytes:dstBuffer length:2048];
            stream.dst_ptr  = dstBuffer;
            stream.dst_size = 2048;
        }
    }

    NSData *result;
    if (rc == COMPRESSION_STATUS_END) {
        if (stream.dst_ptr > dstBuffer) {
            [output appendBytes:dstBuffer length:(stream.dst_ptr - dstBuffer)];
        }
        result = output;
    } else {
        if (error) *error = [NSString stringWithFormat:@"LZMA(XZ) Decompression stream failed with error code: (%d)", rc];
        result = self;
    }
    compression_stream_destroy(&stream);
    free(dstBuffer);
    return result;
}

#pragma mark - Format detection

- (BOOL)isBZippedData {
    if ([self length] < 3) return NO;
    const unsigned char *b = (const unsigned char *)[self bytes];
    return b[0] == 'B' && b[1] == 'Z' && b[2] == 'h';
}

- (BOOL)isGZippedData {
    if ([self length] < 3) return NO;
    const unsigned char *b = (const unsigned char *)[self bytes];
    return b[0] == 0x1f && b[1] == 0x8b && b[2] == 0x08;
}

- (BOOL)isXZippedData {
    if ([self length] < 6) return NO;
    const unsigned char *b = (const unsigned char *)[self bytes];
    return b[0] == 0xFD && b[1] == '7' && b[2] == 'z' && b[3] == 'X' && b[4] == 'Z' && b[5] == 0x00;
}

- (BOOL)isLZMAZippedData {
    if ([self length] < 3) return NO;
    const unsigned char *b = (const unsigned char *)[self bytes];
    return b[0] == 0xFD && b[1] == 0x00 && b[2] == 0x00;
}

- (BOOL)isLZFSEZippedData {
    if ([self length] < 4) return NO;
    const unsigned char *b = (const unsigned char *)[self bytes];
    return b[0] == 'b' && b[1] == 'v' && b[2] == 'x' && b[3] == '2';
}

+ (BOOL)isBZippedDataAtPath:(NSString *)path {
    return [[self dataHeaderForFileAtPath:path] isBZippedData];
}
+ (BOOL)isGZippedDataAtPath:(NSString *)path {
    return [[self dataHeaderForFileAtPath:path] isGZippedData];
}
+ (BOOL)isXZippedDataAtPath:(NSString *)path {
    return [[self dataHeaderForFileAtPath:path] isXZippedData];
}
+ (BOOL)isLZMAZippedDataAtPath:(NSString *)path {
    return [[self dataHeaderForFileAtPath:path] isLZMAZippedData];
}
+ (BOOL)isLZFSEZippedDataAtPath:(NSString *)path {
    return [[self dataHeaderForFileAtPath:path] isLZFSEZippedData];
}

+ (NSData *)dataHeaderForFileAtPath:(NSString *)path {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath:path];
    NSData *data = [fh readDataOfLength:8];
    [fh closeFile];
    return data;
}

#pragma mark - Streaming to file (Compression.framework)

- (BOOL)streamCompressToFile:(NSString *)path
                   algorithm:(DPCompressionAlgorithm)algorithm
                 atomically:(BOOL)atomically {
    return [self streamToFile:path
                    operation:DPCompressionOperationEncode
                    algorithm:algorithm
                   atomically:atomically];
}

- (BOOL)streamDecompressToFile:(NSString *)path
                     algorithm:(DPCompressionAlgorithm)algorithm
                    atomically:(BOOL)atomically {
    return [self streamToFile:path
                    operation:DPCompressionOperationDecode
                    algorithm:algorithm
                   atomically:atomically];
}

- (BOOL)streamToFile:(NSString *)path
           operation:(DPCompressionOperation)operation
           algorithm:(DPCompressionAlgorithm)algorithm
          atomically:(BOOL)atomically {
    if (![self length]) return NO;

    compression_algorithm alg = (compression_algorithm)[[self class] _algorithmForSystemCompressionType:algorithm];
    compression_stream_operation op = (compression_stream_operation)[[self class] _operationForSystemCompressionOperation:operation];
    BOOL isEncode = (op == COMPRESSION_STREAM_ENCODE);

    compression_stream stream;
    if (compression_stream_init(&stream, op, alg) == COMPRESSION_STATUS_ERROR) {
        return NO;
    }

    // The original +dictionaryWithObjects:forKeys:count: call uses both keys == 501
    // and both values == 501 (likely owner/group ids). Preserve that behavior.
    NSNumber *n501 = [NSNumber numberWithInt:501];
    NSDictionary *attrs = [NSDictionary dictionaryWithObjects:@[n501, n501]
                                                      forKeys:@[n501, n501]];

    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[path lastPathComponent]];

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:[path stringByDeletingLastPathComponent]
   withIntermediateDirectories:YES
                   attributes:attrs
                        error:NULL];

    NSString *writePath = atomically ? tmpPath : path;
    [fm createFileAtPath:writePath contents:nil attributes:attrs];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:writePath];

    stream.src_ptr  = (const uint8_t *)[self bytes];
    stream.src_size = [self length];
    uint8_t *dstBuffer = malloc(2048);
    stream.dst_ptr  = dstBuffer;
    stream.dst_size = 2048;

    compression_status status;
    while (1) {
        status = compression_stream_process(&stream, isEncode ? 1 : 0);
        if (status != COMPRESSION_STATUS_OK) break;
        if (stream.dst_size == 0) {
            NSData *chunk = [NSData dataWithBytesNoCopy:dstBuffer length:2048 freeWhenDone:NO];
            [fh writeData:chunk];
            stream.dst_ptr  = dstBuffer;
            stream.dst_size = 2048;
        }
    }

    BOOL success = NO;
    if (status == COMPRESSION_STATUS_ERROR) {
        NSLog(@"Compression stream processing failed");
        [fh closeFile];
        success = NO;
    } else {
        if (status == COMPRESSION_STATUS_END && stream.dst_ptr > dstBuffer) {
            NSData *chunk = [NSData dataWithBytesNoCopy:dstBuffer
                                                 length:(stream.dst_ptr - dstBuffer)
                                           freeWhenDone:NO];
            [fh writeData:chunk];
        }
        [fh closeFile];
        success = YES;

        if (atomically) {
            NSFileManager *mgr = [NSFileManager defaultManager];
            NSURL *dstURL = [NSURL fileURLWithPath:path];
            NSURL *srcURL = [NSURL fileURLWithPath:tmpPath];
            NSError *replaceErr = nil;
            BOOL ok = [mgr replaceItemAtURL:dstURL
                             withItemAtURL:srcURL
                            backupItemName:nil
                                   options:0
                          resultingItemURL:NULL
                                     error:&replaceErr];
            if (replaceErr || !ok) {
                NSLog(@"Error compressing (replace): %@", [replaceErr localizedDescription]);
                NSError *rmErr = nil;
                BOOL rmOk = [mgr removeItemAtPath:path error:&rmErr];
                if (rmErr || !rmOk) {
                    NSLog(@"Error compressing (remove): %@", [rmErr localizedDescription]);
                } else {
                    NSError *moveErr = nil;
                    BOOL moveOk = [mgr moveItemAtPath:tmpPath toPath:path error:&moveErr];
                    if (moveErr || !moveOk) {
                        NSLog(@"Error compressing (move): %@", [moveErr localizedDescription]);
                    }
                }
            }
        }
    }

    compression_stream_destroy(&stream);
    free(dstBuffer);
    return success;
}

#pragma mark - Buffered API

- (instancetype)initWithContentsOfArchive:(NSString *)path
                          usingAlgorithm:(DPCompressionAlgorithm)algorithm {
    NSData *src = [NSData dataWithContentsOfFile:path];
    return (NSData *)[src dataUsingAlgorithm:algorithm
                                   operation:DPCompressionOperationDecode];
}

- (NSData *)compressedDataUsingAlgorithm:(DPCompressionAlgorithm)algorithm {
    return [self dataUsingAlgorithm:algorithm operation:DPCompressionOperationEncode];
}

- (NSData *)dataUsingAlgorithm:(DPCompressionAlgorithm)algorithm
                     operation:(DPCompressionOperation)operation {
    if (![self length]) return nil;

    @autoreleasepool {
        compression_stream_operation op = (compression_stream_operation)[[self class] _operationForSystemCompressionOperation:operation];
        BOOL isEncode = (operation == DPCompressionOperationEncode);
        compression_algorithm alg = (compression_algorithm)[[self class] _algorithmForSystemCompressionType:algorithm];

        compression_stream stream;
        if (compression_stream_init(&stream, op, alg) == COMPRESSION_STATUS_ERROR) {
            return nil;
        }

        stream.src_ptr  = (const uint8_t *)[self bytes];
        stream.src_size = [self length];
        uint8_t *dstBuffer = malloc(1024);
        stream.dst_ptr  = dstBuffer;
        stream.dst_size = 1024;

        NSMutableData *output = [NSMutableData new];
        compression_status status;
        while (1) {
            status = compression_stream_process(&stream, isEncode ? 1 : 0);
            if (status != COMPRESSION_STATUS_OK) break;
            if (stream.dst_size == 0) {
                [output appendBytes:dstBuffer length:1024];
                stream.dst_ptr  = dstBuffer;
                stream.dst_size = 1024;
            }
        }

        NSData *result = nil;
        if (status == COMPRESSION_STATUS_ERROR) {
            compression_stream_destroy(&stream);
            free(dstBuffer);
            return nil;
        }
        if (status == COMPRESSION_STATUS_END && stream.dst_ptr > dstBuffer) {
            [output appendBytes:dstBuffer length:(stream.dst_ptr - dstBuffer)];
        }
        compression_stream_destroy(&stream);
        free(dstBuffer);
        result = [output copy];
        return result;
    }
}

#pragma mark - Internals

+ (int)_algorithmForSystemCompressionType:(DPCompressionAlgorithm)type {
    // Matches binary: values >3 select LZFSE (0x801=2049), otherwise LZ4 (0x100=256).
    if ((NSUInteger)type > 3) {
        return 2049; // COMPRESSION_LZFSE
    }
    return 256;      // COMPRESSION_LZ4
}

+ (int)_operationForSystemCompressionOperation:(DPCompressionOperation)op {
    // 0 -> encode (0), 1 -> decode (1). The original returns `op == 1`.
    return (op == DPCompressionOperationDecode) ? 1 : 0;
}

@end
