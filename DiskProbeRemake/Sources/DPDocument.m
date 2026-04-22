#import "DPDocument.h"

@implementation DPDocument

+ (BOOL)isBinaryPlistData:(NSData *)data {
    const unsigned char *bytes = (const unsigned char *)[data bytes];
    return bytes[0] == 'b'
        && bytes[1] == 'p'
        && bytes[2] == 'l'
        && bytes[3] == 'i'
        && bytes[4] == 's'
        && bytes[5] == 't';
}

- (id)contentsForType:(NSString *)typeName error:(NSError **)outError {
    return [self.stringValue dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)loadFromContents:(id)contents ofType:(NSString *)typeName error:(NSError **)outError {
    NSData *data = (NSData *)contents;

    if (![data respondsToSelector:@selector(length)] || [data length] == 0) {
        return NO;
    }

    UIImage *image = [[UIImage alloc] initWithData:data];
    if (image) {
        self.imageValue = image;
        self.stringValue = nil;
        return YES;
    }

    if ([typeName isEqualToString:@"com.apple.property-list"]
        || [DPDocument isBinaryPlistData:data]) {
        id plist = [NSPropertyListSerialization propertyListWithData:data
                                                              options:0
                                                               format:NULL
                                                                error:NULL];
        NSData *converted = [NSPropertyListSerialization dataWithPropertyList:plist
                                                                       format:NSPropertyListXMLFormat_v1_0
                                                                      options:0
                                                                        error:NULL];
        data = converted;
    }

    NSString *string = [[NSString alloc] initWithBytes:[data bytes]
                                                length:[data length]
                                              encoding:NSUTF8StringEncoding];
    if (!string) {
        string = [[NSString alloc] initWithBytes:[data bytes]
                                          length:[data length]
                                        encoding:NSASCIIStringEncoding];
    }
    if (!string) {
        string = [[NSString alloc] initWithBytes:[data bytes]
                                          length:[data length]
                                        encoding:NSUnicodeStringEncoding];
    }

    if (string) {
        self.stringValue = string;
        self.imageValue = nil;
    } else {
        NSURL *fileURL = [self fileURL];
        UIDocumentInteractionController *controller = [UIDocumentInteractionController interactionControllerWithURL:fileURL];
        UIImage *icon = [[controller icons] firstObject];
        self.imageValue = icon;
        self.stringValue = nil;
    }

    return YES;
}

@end
