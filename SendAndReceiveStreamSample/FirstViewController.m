//
//  FirstViewController.m
//  SendAndReceiveStreamSample
//
//  Created by Mac Mini on 13/2/7.
//  Copyright (c) 2013年 E-Lead. All rights reserved.
//

#import "FirstViewController.h"
#import "NetworkManager.h"
#import "NetworkManager.h"
#import "QNetworkAdditions.h"

enum {
    kSendBufferSize = 32768
    //byte
};

@interface FirstViewController ()

@property (nonatomic, assign, readonly ) BOOL               isStarted;
@property (nonatomic, assign, readonly ) BOOL               isSending;
@property (nonatomic, assign, readwrite) CFSocketRef        listeningSocket;
@property (nonatomic, strong, readwrite) NSOutputStream *   networkStream;
@property (nonatomic, strong, readwrite) NSInputStream *    fileStream;
@property (nonatomic, assign, readonly ) uint8_t *          buffer;
@property (nonatomic, assign, readwrite) size_t             bufferOffset;
@property (nonatomic, assign, readwrite) size_t             bufferLimit;

@end

@implementation FirstViewController
{
    uint8_t _buffer[kSendBufferSize];
}


@synthesize overlayViewController,capturedImages,img,cameraImageView;
@synthesize networkStream   = _networkStream;
@synthesize listeningSocket = _listeningSocket;
@synthesize fileStream      = _fileStream;
@synthesize bufferOffset    = _bufferOffset;
@synthesize bufferLimit     = _bufferLimit;

- (uint8_t *)buffer
{
    return self->_buffer;//回傳buffer 的指標
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        self.title = NSLocalizedString(@"First", @"First");
        self.tabBarItem.image = [UIImage imageNamed:@"first"];
    }
    return self;
}
							
- (void)viewDidLoad{
    [super viewDidLoad];
    self.capturedImages = [[NSMutableArray alloc] init];
    
    self.overlayViewController = [[[OverlayViewController alloc] initWithNibName:@"OverlayViewController" bundle:nil] autorelease];
    self.overlayViewController.delegate = self;
    
    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapTheCameraImage)];
    tapRecognizer.delegate = self;
    tapRecognizer.numberOfTapsRequired = 1;
    [cameraImageView addGestureRecognizer:tapRecognizer];
    cameraImageView.userInteractionEnabled = YES;
}

//重頭戲
- (IBAction)sendStream:(id)sender{
    if ([self.capturedImages objectAtIndex:0] != nil ) {
        if ( ! self.isSending ) {
            //        NSString *  filePath;
            // Use the tag on the button to determine which image to send.
            //        filePath = [[NetworkManager sharedInstance] pathForTestImage:sender.tag];
            //先把檔案放大10~1000倍 在傳送
            //        assert(filePath != nil);
            //
            [self startSend];
        }
        else{
            NSLog(@"還在送");
        }
    }
}

- (void)startSend{
    NSOutputStream *    output;
    BOOL                success;
    NSNetService *      netService;
        
    assert(self.networkStream == nil);      // don't tap send twice in a row!
    assert(self.fileStream == nil);         // 同上
    
    // Open a stream for the file we're going to send.
    // 打開Stream 給我們要送的檔案
    
    //    self.fileStream = [NSInputStream inputStreamWithFileAtPath:filePath];
    NSData *dataObj = UIImageJPEGRepresentation([self.capturedImages objectAtIndex:[self.capturedImages count] -1 ], 1);
    self.fileStream = [NSInputStream inputStreamWithData:dataObj];
    assert(self.fileStream != nil);
    
    [self.fileStream open];
    
    // Open a stream to the server, finding the server via Bonjour.  Then configure
    // the stream for async operation.
    // 打開到Server 的Stream ，Server 是透過Bonjour 找到的，然後設定Stream 非同步選項 ( 跑 TCP )
    
    netService = [[NSNetService alloc] initWithDomain:@"local." type:@"_x-SNSUpload._tcp." name:@"Test"];
    assert(netService != nil);
    
    // Until <rdar://problem/6868813> is fixed, we have to use our own code to open the streams
    // rather than call -[NSNetService getInputStream:outputStream:].  See the comments in
    // QNetworkAdditions.m for the details.
    
    success = [netService qNetworkAdditions_getInputStream:NULL outputStream:&output];//<- 剩這支
    
    assert(success);
    
    self.networkStream = output;
    self.networkStream.delegate = self;
    [self.networkStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.networkStream open];
    // 告訴UI說正在送了
    [self sendDidStart];
}

- (void)sendDidStart{
    
    [[NetworkManager sharedInstance] didStartNetworkOperation];
}

- (void)updateStatus:(NSString *)statusString
{
    assert(statusString != nil);
    [sendBtn setTitle:statusString forState:UIControlStateNormal];
}

// 在NSStream 裡面處理如果NSStreamEventError 或者 送完Stream 就算呼叫關閉Stream的
// Start send 的時候並不會被call ，而是Receive端開啓的時候才會執行這邊
- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
// An NSStream delegate callback that's called when events happen on our
// network stream.
{
    assert(aStream == self.networkStream);
#pragma unused(aStream)
    
    switch (eventCode) {
        case NSStreamEventOpenCompleted: {
            [self updateStatus:@"Opened connection"];
        } break;
        case NSStreamEventHasBytesAvailable: {
            assert(NO);     // 這不會發生在 output stream
        } break;
            
        case NSStreamEventHasSpaceAvailable: {
            [self updateStatus:@"傳送中"];
            
            // If we don't have any data buffered, go read the next chunk of data.
            
            if (self.bufferOffset == self.bufferLimit) {
                NSInteger   bytesRead;
                
                bytesRead = [self.fileStream read:self.buffer maxLength:kSendBufferSize];
                if (bytesRead == -1) {
                    [self stopSendWithStatus:@"File read error"];
                } else if (bytesRead == 0) {
                    [self stopSendWithStatus:nil];//送完了所以要Close Stream
                } else {
                    self.bufferOffset = 0;
                    self.bufferLimit  = bytesRead;
                }
            }
            // If we're not out of data completely, send the next chunk.
            if (self.bufferOffset != self.bufferLimit) {
                NSInteger   bytesWritten;
                bytesWritten = [self.networkStream write:&self.buffer[self.bufferOffset] maxLength:self.bufferLimit - self.bufferOffset];
                assert(bytesWritten != 0);
                if (bytesWritten == -1) {
                    [self stopSendWithStatus:@"Network write error"];
                } else {
                    self.bufferOffset += bytesWritten;
                }
            }
        } break;
        case NSStreamEventErrorOccurred: {
            [self stopSendWithStatus:@"Stream open error"];
        } break;
        case NSStreamEventEndEncountered: {
            // ignore
        } break;
        default: {
            assert(NO);
        } break;
    }
}

//判斷是否在傳送中
- (BOOL)isSending
{
    return (self.networkStream != nil);
}

- (void)tapTheCameraImage{
    [self showImagePicker:UIImagePickerControllerSourceTypeCamera];
}

- (void)showImagePicker:(UIImagePickerControllerSourceType)sourceType
{
    if (self.cameraImageView.isAnimating)
        [self.cameraImageView stopAnimating];
    if ([UIImagePickerController isSourceTypeAvailable:sourceType]){
        [self.overlayViewController setupImagePicker:sourceType];
        [self presentViewController:self.overlayViewController.imagePickerController animated:YES completion:nil];
    }
}

#pragma mark OverlayViewControllerDelegate
// as a delegate we are being told a picture was taken
- (void)didTakePicture:(UIImage *)picture{
   [self.capturedImages addObject:picture];
}

// as a delegate we are told to finished with the camera
- (void)didFinishWithCamera{
    
    [self dismissViewControllerAnimated:YES completion:NULL];
    
    if ([self.capturedImages count] > 0)
    {
        if ([self.capturedImages count] == 1)
        {
            // we took a single shot
            [self.cameraImageView setImage:[self.capturedImages objectAtIndex:0]];
        }
        else{
            [self.cameraImageView setImage:[self.capturedImages objectAtIndex:[self.capturedImages count]-1]];
        }
    }
    NSLog(@"現在拍了幾張？ %i",[self.capturedImages count]);
}

#pragma mark - Stop Stream

- (void)stopSendWithStatus:(NSString *)statusString
{
    if (self.networkStream != nil) {
        [self.networkStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        self.networkStream.delegate = nil;
        [self.networkStream close];
        self.networkStream = nil;
    }
    if (self.fileStream != nil) {
        [self.fileStream close];
        self.fileStream = nil;
    }
    self.bufferOffset = 0;
    self.bufferLimit  = 0;
    [self sendDidStopWithStatus:statusString];
    [self performSelector:@selector(delayUpdateBtnStatus) withObject:nil afterDelay:1.5];
}

- (void)delayUpdateBtnStatus{
    if ([self isSending]) {
        [sendBtn setTitle:@"STOP" forState:UIControlStateNormal];
    }
    else
        [sendBtn setTitle:@"SEND" forState:UIControlStateNormal];
}

- (void)sendDidStopWithStatus:(NSString *)statusString
{
    if (statusString == nil) {
        statusString = @"傳送成功";
    }
    [self updateStatus:statusString];
    [[NetworkManager sharedInstance] didStopNetworkOperation];
}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
