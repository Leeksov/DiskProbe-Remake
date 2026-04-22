#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// System-level compression-type enum used by the higher-level stream APIs.
// Values <= 3 map to LZ4, higher values map to LZFSE (matches the
// behavior of +_algorithmForSystemCompressionType: in the original binary).
typedef NS_ENUM(NSUInteger, DPCompressionAlgorithm) {
    DPCompressionAlgorithmLZ4   = 0,
    DPCompressionAlgorithmZLIB  = 1,
    DPCompressionAlgorithmLZMA  = 2,
    DPCompressionAlgorithmLZ4Raw = 3,
    DPCompressionAlgorithmLZFSE = 4,
};

typedef NS_ENUM(NSUInteger, DPCompressionOperation) {
    DPCompressionOperationEncode = 0,
    DPCompressionOperationDecode = 1,
};

@interface NSData (DPCompression)

// ---- BZ2 ----------------------------------------------------------------
- (NSData *)BZUnzippedData;
- (NSData *)BZUnzippedData:(NSString * _Nullable * _Nullable)error;

// ---- GZ -----------------------------------------------------------------
- (NSData *)GZUnzippedData;
- (NSData *)GZUnzippedData:(NSString * _Nullable * _Nullable)error;

// ---- XZ / LZMA ----------------------------------------------------------
- (NSData *)XZUnzippedData;
- (NSData *)XZUnzippedData:(NSString * _Nullable * _Nullable)error;

// ---- Format detection --------------------------------------------------
- (BOOL)isBZippedData;
- (BOOL)isGZippedData;
- (BOOL)isXZippedData;
- (BOOL)isLZMAZippedData;
- (BOOL)isLZFSEZippedData;

+ (BOOL)isBZippedDataAtPath:(NSString *)path;
+ (BOOL)isGZippedDataAtPath:(NSString *)path;
+ (BOOL)isXZippedDataAtPath:(NSString *)path;
+ (BOOL)isLZMAZippedDataAtPath:(NSString *)path;
+ (BOOL)isLZFSEZippedDataAtPath:(NSString *)path;

+ (NSData *)dataHeaderForFileAtPath:(NSString *)path;

// ---- Streaming compression (Compression.framework) ---------------------
- (BOOL)streamCompressToFile:(NSString *)path
                   algorithm:(DPCompressionAlgorithm)algorithm
                 atomically:(BOOL)atomically;
- (BOOL)streamDecompressToFile:(NSString *)path
                     algorithm:(DPCompressionAlgorithm)algorithm
                    atomically:(BOOL)atomically;
- (BOOL)streamToFile:(NSString *)path
           operation:(DPCompressionOperation)operation
           algorithm:(DPCompressionAlgorithm)algorithm
          atomically:(BOOL)atomically;

// ---- Buffered (de)compression ------------------------------------------
- (nullable instancetype)initWithContentsOfArchive:(NSString *)path
                                    usingAlgorithm:(DPCompressionAlgorithm)algorithm;
- (nullable NSData *)compressedDataUsingAlgorithm:(DPCompressionAlgorithm)algorithm;
- (nullable NSData *)dataUsingAlgorithm:(DPCompressionAlgorithm)algorithm
                              operation:(DPCompressionOperation)operation;

// ---- Internal helpers (exposed for parity with original class) ---------
+ (int)_algorithmForSystemCompressionType:(DPCompressionAlgorithm)type;
+ (int)_operationForSystemCompressionOperation:(DPCompressionOperation)op;

@end

NS_ASSUME_NONNULL_END
