/*
    File:       NetworkManager.m

    Contains:   Shared state and utilities for networking.

    Written by: DTS

    Copyright:  Copyright (c) 2009-2012 Apple Inc. All Rights Reserved.

    Disclaimer: IMPORTANT: This Apple software is supplied to you by Apple Inc.
                ("Apple") in consideration of your agreement to the following
                terms, and your use, installation, modification or
                redistribution of this Apple software constitutes acceptance of
                these terms.  If you do not agree with these terms, please do
                not use, install, modify or redistribute this Apple software.

                In consideration of your agreement to abide by the following
                terms, and subject to these terms, Apple grants you a personal,
                non-exclusive license, under Apple's copyrights in this
                original Apple software (the "Apple Software"), to use,
                reproduce, modify and redistribute the Apple Software, with or
                without modifications, in source and/or binary forms; provided
                that if you redistribute the Apple Software in its entirety and
                without modifications, you must retain this notice and the
                following text and disclaimers in all such redistributions of
                the Apple Software. Neither the name, trademarks, service marks
                or logos of Apple Inc. may be used to endorse or promote
                products derived from the Apple Software without specific prior
                written permission from Apple.  Except as expressly stated in
                this notice, no other rights or licenses, express or implied,
                are granted by Apple herein, including but not limited to any
                patent rights that may be infringed by your derivative works or
                by other works in which the Apple Software may be incorporated.

                The Apple Software is provided by Apple on an "AS IS" basis. 
                APPLE MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING
                WITHOUT LIMITATION THE IMPLIED WARRANTIES OF NON-INFRINGEMENT,
                MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE, REGARDING
                THE APPLE SOFTWARE OR ITS USE AND OPERATION ALONE OR IN
                COMBINATION WITH YOUR PRODUCTS.

                IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT,
                INCIDENTAL OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
                TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
                DATA, OR PROFITS; OR BUSINESS INTERRUPTION) ARISING IN ANY WAY
                OUT OF THE USE, REPRODUCTION, MODIFICATION AND/OR DISTRIBUTION
                OF THE APPLE SOFTWARE, HOWEVER CAUSED AND WHETHER UNDER THEORY
                OF CONTRACT, TORT (INCLUDING NEGLIGENCE), STRICT LIABILITY OR
                OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE POSSIBILITY OF
                SUCH DAMAGE.

*/

#import "NetworkManager.h"

@interface NetworkManager ()

// read/write redeclaration of public read-only property

@property (nonatomic, assign, readwrite) NSUInteger     networkOperationCount;

@end

@implementation NetworkManager

@synthesize networkOperationCount = _networkOperationCount;

+ (NetworkManager *)sharedInstance
{
    static dispatch_once_t  onceToken;
    static NetworkManager * sSharedInstance;

    dispatch_once(&onceToken, ^{
        sSharedInstance = [[NetworkManager alloc] init];
    });
    return sSharedInstance;
}

- (NSString *)pathForTestImage:(NSUInteger)imageNumber
    // In order to fully test the send and receive code paths, we need some really big 
    // files.  Rather than carry theshe files around in our binary, we synthesise them. 
    // Specifically, for each test image, we expand the image by an order of magnitude, 
    // based on its image number.  That is, image 1 is not expanded, image 2 
    // gets expanded 10 times, and so on.  We expand the image by simply copying it 
    // to the temporary directory, writing the same data to the file over and over 
    // again.
{
    NSLog(@"IMAGE NUMBER %i",imageNumber);
    NSUInteger          power;
    NSUInteger          expansionFactor;
    NSString *          originalFilePath;
    NSString *          bigFilePath;
    NSFileManager *     fileManager;
    NSDictionary *      attrs;
    unsigned long long  originalFileSize;
    unsigned long long  bigFileSize;
    
    assert( (imageNumber >= 1) && (imageNumber <= 4) );

    // Argh, C has no built-in power operator, so I have to do 10 ** (imageNumber - 1)
    // in floating point and then cast back to integer.  Fortunately the range 
    // of values is small enough (1..1000) that floating point isn't going 
    // to cause me any problems.
    // On the simulator we expand by an extra order of magnitude; Macs are fast!
    
    power = imageNumber - 1;
    #if TARGET_IPHONE_SIMULATOR
        power += 1;
    #endif
    
    expansionFactor = (NSUInteger) pow(10, power);//10的 1 , 2, 3, 4 次方10,100,1000,10000
    
    fileManager = [NSFileManager defaultManager];
    assert(fileManager != nil);
    
    // Calculate paths to both the original file and the expanded file.
    
    originalFilePath = [[NSBundle mainBundle] pathForResource:[NSString stringWithFormat:@"TestImage%zu", (size_t) imageNumber] ofType:@"png"];
    NSLog(@"originalFilePath %@",originalFilePath);//應該是在Bundle Resource 裡面
    assert(originalFilePath != nil);
    
    bigFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"TestImage%zu.png", (size_t) imageNumber]];//指到tmp底下 ???
    assert(bigFilePath != nil);
    
    // 取得兩者的檔案大小.
    //NSDictionary *attrs;
    attrs = [fileManager attributesOfItemAtPath:originalFilePath error:NULL];
    assert(attrs != nil);
    
    NSLog(@"attrs %@",attrs);//取得原始檔案的架構
    /*
        EX.
        NSFileCreationDate = "2013-02-06 04:15:32 +0000";
        NSFileExtensionHidden = 0;
        NSFileGroupOwnerAccountID = 20;
        NSFileGroupOwnerAccountName = staff;
        NSFileModificationDate = "2013-02-06 04:15:32 +0000";
        NSFileOwnerAccountID = 501;
        NSFileOwnerAccountName = macmini;
        NSFilePosixPermissions = 420;
        NSFileReferenceCount = 1;
        NSFileSize = 6459;
        NSFileSystemFileNumber = 4321737;
        NSFileSystemNumber = 16777218;
        NSFileType = NSFileTypeRegular;
     */
    
    originalFileSize = [[attrs objectForKey:NSFileSize] unsignedLongLongValue];

    attrs = [fileManager attributesOfItemAtPath:bigFilePath error:NULL];
    
    NSLog(@"attrs %@",attrs);
    /*  
        NSFileCreationDate = "2013-02-06 05:27:22 +0000";
        NSFileExtensionHidden = 0;
        NSFileGroupOwnerAccountID = 20;
        NSFileGroupOwnerAccountName = staff;
        NSFileModificationDate = "2013-02-06 05:27:23 +0000";
        NSFileOwnerAccountID = 501;
        NSFileOwnerAccountName = macmini;
        NSFilePosixPermissions = 420;
        NSFileReferenceCount = 1;
        NSFileSize = 61710000;
        NSFileSystemFileNumber = 4333215;
        NSFileSystemNumber = 16777218;
        NSFileType = NSFileTypeRegular;
    */
    //還沒有copy一份在TMP底下
    if (attrs == NULL) {
        bigFileSize = 0;
    } else {
        bigFileSize = [[attrs objectForKey:NSFileSize] unsignedLongLongValue];
    }
    
    // If the expanded file is missing, or the wrong size, create it from scratch.
    // 如果檔案遺失或者size不對(有可能是之前的圖片)，就會從頭開始建立
    if (bigFileSize != (originalFileSize * expansionFactor)) {
        NSOutputStream *    bigFileStream;
        NSData *            data;
        const uint8_t *     dataBuffer;
        NSUInteger          dataLength;
        NSUInteger          dataOffset;
        NSUInteger          counter;

        NSLog(@"%5zu - %@", (size_t) expansionFactor, bigFilePath);

        data = [NSData dataWithContentsOfMappedFile:originalFilePath];//NSData 從OriginalFilePath接過來
        assert(data != nil);
        //BUFFER & File Length
        dataBuffer = [data bytes];
        dataLength = [data length];
        
        bigFileStream = [NSOutputStream outputStreamToFileAtPath:bigFilePath append:NO];
        assert(bigFileStream != NULL);
        
        [bigFileStream open];//Stream OPEN !!!! 是什麼意思啊 ...
        //要放大10倍寫檔案
        for (counter = 0; counter < expansionFactor; counter++) {
            dataOffset = 0;
            while (dataOffset != dataLength) {
                NSInteger       bytesWritten;//寫了多少檔案
                bytesWritten = [bigFileStream write:&dataBuffer[dataOffset] maxLength:dataLength - dataOffset];//寫入的動作
                assert(bytesWritten > 0);
                dataOffset += bytesWritten;
            }
        }
        [bigFileStream close];//用for 跑OutputStream，跑完才Close
    }
    NSLog(@"bigFilePath %@",bigFilePath);
    return bigFilePath;
}

- (NSString *)pathForTemporaryFileWithPrefix:(NSString *)prefix
{
    NSString *  result;
    CFUUIDRef   uuid;
    NSString *  uuidStr;
    
    uuid = CFUUIDCreate(NULL);
    assert(uuid != NULL);
    
    uuidStr = CFBridgingRelease( CFUUIDCreateString(NULL, uuid) );
    
    result = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", prefix, uuidStr]];
    assert(result != nil);
    
    CFRelease(uuid);
    
    return result;
}

- (void)didStartNetworkOperation
{
    // If you start a network operation off the main thread, you'll have to update this code 
    // to ensure that any observers of this property are thread safe.
    assert([NSThread isMainThread]);
    self.networkOperationCount += 1;
}

- (void)didStopNetworkOperation
{
    // If you stop a network operation off the main thread, you'll have to update this code 
    // to ensure that any observers of this property are thread safe.
    assert([NSThread isMainThread]);
    assert(self.networkOperationCount > 0);
    self.networkOperationCount -= 1;
}

@end
