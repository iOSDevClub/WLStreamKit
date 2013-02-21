//
//  SecondViewController.m
//  SendAndReceiveStreamSample
//
//  Created by Mac Mini on 13/2/7.
//  Copyright (c) 2013年 E-Lead. All rights reserved.
//

#import "SecondViewController.h"
#import "NetworkManager.h"
#include <CFNetwork/CFNetwork.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

@interface SecondViewController ()

// UI
@property (nonatomic, strong, readwrite) IBOutlet UIImageView *imageView;
@property (nonatomic, strong, readwrite) IBOutlet UIButton *startOrStopButton;

- (IBAction)startOrStopAction:(id)sender;

// Private properties
@property (nonatomic, assign, readonly ) BOOL               isStarted;
@property (nonatomic, assign, readonly ) BOOL               isReceiving;
@property (nonatomic, strong, readwrite) NSNetService *     netService;
@property (nonatomic, assign, readwrite) CFSocketRef        listeningSocket;
@property (nonatomic, strong, readwrite) NSInputStream *    networkStream;
@property (nonatomic, strong, readwrite) NSOutputStream *   fileStream;
@property (nonatomic, copy,   readwrite) NSString *         filePath;

- (void)stopServer:(NSString *)reason;

@end

@implementation SecondViewController

@synthesize netService      = _netService;
@synthesize networkStream   = _networkStream;
@synthesize listeningSocket = _listeningSocket;
@synthesize fileStream      = _fileStream;
@synthesize filePath        = _filePath;
@synthesize imageView         = _imageView;
@synthesize startOrStopButton = _startOrStopButton;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        self.title = NSLocalizedString(@"Second", @"Second");
        self.tabBarItem.image = [UIImage imageNamed:@"second"];
    }
    return self;
}

- (IBAction)startOrStopAction:(id)sender{
    if (self.isStarted) {
        [self stopServer:nil];
    } else {
        [self startServer];
    }
}

- (void)stopServer:(NSString *)reason{
    if (self.isReceiving) {
        [self stopReceiveWithStatus:@"Cancelled"];
    }
    if (self.netService != nil) {
        [self.netService stop];
        self.netService = nil;
    }
    if (self.listeningSocket != NULL) {
        CFSocketInvalidate(self.listeningSocket);
        CFRelease(self->_listeningSocket);
        self->_listeningSocket = NULL;
    }
    [self serverDidStopWithReason:reason];
}

- (void)serverDidStopWithReason:(NSString *)reason{
    if (reason == nil) {
        reason = @"Stopped";
    }
    [self.startOrStopButton setTitle:reason forState:UIControlStateNormal];
}

- (void)stopReceiveWithStatus:(NSString *)statusString
{
    if (self.networkStream != nil) {
        self.networkStream.delegate = nil;
        [self.networkStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
        [self.networkStream close];
        self.networkStream = nil;
    }
    if (self.fileStream != nil) {
        [self.fileStream close];
        self.fileStream = nil;
    }
    [self receiveDidStopWithStatus:statusString];
    self.filePath = nil;
}

- (void)receiveDidStopWithStatus:(NSString *)statusString{
    if (statusString == nil) {
        assert(self.filePath != nil);
        self.imageView.image = [UIImage imageWithContentsOfFile:self.filePath];
        statusString = @"接收成功";
    }
    [_startOrStopButton setTitle:statusString forState:UIControlStateNormal];
    [[NetworkManager sharedInstance] didStopNetworkOperation];
    [self performSelector:@selector(delayUpdateBtnStatus) withObject:nil afterDelay:1.5];
}

- (void)delayUpdateBtnStatus{
    if ([self isStarted]) {
        [_startOrStopButton setTitle:@"Stop Server" forState:UIControlStateNormal];
    }
    else
        [_startOrStopButton setTitle:@"Start Server" forState:UIControlStateNormal];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
}

#pragma mark * Core transfer code

// This is the code that actually does the networking.

- (BOOL)isStarted
{
    return (self.netService != nil);
}

- (BOOL)isReceiving
{
    return (self.networkStream != nil);
}

- (void)startReceive:(int)fd
{
    CFReadStreamRef     readStream;
    
    assert(fd >= 0);
    assert(self.networkStream == nil);      // can't already be receiving
    assert(self.fileStream == nil);         // 同上
    assert(self.filePath == nil);           // ditto
    
    // Open a stream for the file we're going to receive into.
    // 開一個Stream 準備收檔
    self.filePath = [[NetworkManager sharedInstance] pathForTemporaryFileWithPrefix:@"Receive"];
    assert(self.filePath != nil);
    
    //File Path是一個隨機的路徑在
    
    self.fileStream = [NSOutputStream outputStreamToFileAtPath:self.filePath append:NO];
    
    assert(self.fileStream != nil);
    
    [self.fileStream open];
    
    // Open a stream based on the existing socket file descriptor.  Then configure
    // the stream for async operation.
    CFStreamCreatePairWithSocket(NULL, fd, &readStream, NULL);
    
    assert(readStream != NULL);
    self.networkStream = (__bridge NSInputStream *) readStream;
    
    CFRelease(readStream);
    
    [self.networkStream setProperty:(id)kCFBooleanTrue forKey:(NSString *)kCFStreamPropertyShouldCloseNativeSocket];
    self.networkStream.delegate = self;
    [self.networkStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
    [self.networkStream open];
    // Tell the UI we're receiving.
    [self receiveDidStart];
}

- (void)receiveDidStart
{
    [_startOrStopButton setTitle:@"Receiving" forState:UIControlStateNormal];
    self.imageView.image = [UIImage imageNamed:@"NoImage.png"];
    [[NetworkManager sharedInstance] didStartNetworkOperation];
}

 void AcceptCallback(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
// Called by CFSocket when someone connects to our listening socket.
// This implementation just bounces the request up to Objective-C.
{
    SecondViewController *  obj;
    
#pragma unused(type)
    assert(type == kCFSocketAcceptCallBack);
#pragma unused(address)
    // assert(address == NULL);
    assert(data != NULL);
    
    obj = (__bridge SecondViewController *) info;
    assert(obj != nil);
    
    assert(s == obj->_listeningSocket);
#pragma unused(s)
    
    [obj acceptConnection:*(int *)data];
}

- (void)acceptConnection:(int)fd
{
    int     junk;
    
    // If we already have a connection, reject this new one.  This is one of the
    // big simplifying assumptions in this code.  A real server should handle
    // multiple simultaneous connections.
    
    if ( self.isReceiving ) {
        junk = close(fd);
        assert(junk == 0);
    } else {
        [self startReceive:fd];
    }
}

- (void)startServer{
    BOOL                success;
    int                 err;
    int                 fd;
    int                 junk;
    struct sockaddr_in  addr;
    NSUInteger          port;
    
    // Create a listening socket and use CFSocket to integrate it into our
    // runloop.  We bind to port 0, which causes the kernel to give us
    // any free port, then use getsockname to find out what port number we
    // actually got.
    
    port = 0;
    
    fd = socket(AF_INET, SOCK_STREAM, 0);
    success = (fd != -1);
    //success 一直成立才會往下做
    if (success) {
        memset(&addr, 0, sizeof(addr));
        addr.sin_len    = sizeof(addr);
        addr.sin_family = AF_INET;
        addr.sin_port   = 0;
        addr.sin_addr.s_addr = INADDR_ANY;
        err = bind(fd, (const struct sockaddr *) &addr, sizeof(addr));
        success = (err == 0);
    }
    if (success) {
        err = listen(fd, 5);
        success = (err == 0);
    }
    if (success) {
        socklen_t   addrLen;
        addrLen = sizeof(addr);
        err = getsockname(fd, (struct sockaddr *) &addr, &addrLen);
        success = (err == 0);
        if (success) {
            assert(addrLen == sizeof(addr));
            port = ntohs(addr.sin_port);
            //PORT 會亂跳！
        }
    }
    if (success) {
        CFSocketContext context = { 0, (__bridge void *) self, NULL, NULL, NULL };
        assert(self->_listeningSocket == NULL);
        self->_listeningSocket = CFSocketCreateWithNative(
                                                          NULL,
                                                          fd,
                                                          kCFSocketAcceptCallBack,
                                                          AcceptCallback, //typedef void (*CFSocketCallBack)(CFSocketRef s, CFSocketCallBackType type, CFDataRef address, const void *data, void *info);
                                                          &context
                                                          );
        success = (self->_listeningSocket != NULL);
        if (success) {
            CFRunLoopSourceRef  rls;
            fd = -1;        // listeningSocket is now responsible for closing fd
            rls = CFSocketCreateRunLoopSource(NULL, self.listeningSocket, 0);
            assert(rls != NULL);
            CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, kCFRunLoopDefaultMode);
            CFRelease(rls);
        }
    }
    // 現在才可以開始做NSService 的註冊跟廣播 ...
    // Now register our service with Bonjour.  See the comments in -netService:didNotPublish:
    // for more info about this simplifying assumption.
    
    if (success) {
        //inDomain 如果給@"" 就是不指定Domain
        self.netService = [[NSNetService alloc] initWithDomain:@"local." type:@"_x-SNSUpload._tcp." name:@"Test" port:port];
        success = (self.netService != nil);
    }//Service register 之後再Publish ...
    if (success) {
        self.netService.delegate = self;
        [self.netService publishWithOptions:NSNetServiceNoAutoRename];
        // continues in -netServiceDidPublish: or -netService:didNotPublish: ...
    }
    
    // Clean up after failure.
    //Publish 成功之後更改UI的狀態
    if ( success ) {
        assert(port != 0);
        [self serverDidStartOnPort:port];
    } else {
        [self stopServer:@"Start failed"];
        if (fd != -1) {
            junk = close(fd);// ???這啥小???
            assert(junk == 0);
        }
    }
}

- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict{
    // A NSNetService delegate callback that's called if our Bonjour registration
    // fails.  We respond by shutting down the server.
    //
    // This is another of the big simplifying assumptions in this sample.
    // A real server would use the real name of the device for registrations,
    // and handle automatically renaming the service on conflicts.  A real
    // client would allow the user to browse for services.  To simplify things
    // we just hard-wire the service name in the client and, in the server, fail
    // if there's a service name conflict.
#pragma unused(sender)
    assert(sender == self.netService);
#pragma unused(errorDict)
    
    [self stopServer:@"Registration failed"];
}


- (void)updateStatus:(NSString *)statusString
{
    assert(statusString != nil);
    [self.startOrStopButton setTitle:statusString forState:UIControlStateNormal];
}


//這邊處理收到的STREAM
- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
// An NSStream delegate callback that's called when events happen on our
// network stream.
{
    assert(aStream == self.networkStream);//NSInputStream
#pragma unused(aStream)
    switch (eventCode) {
        case NSStreamEventOpenCompleted: {
            [self updateStatus:@"Opened connection"];
        } break;
        case NSStreamEventHasBytesAvailable: {
            NSInteger       bytesRead;
            uint8_t         buffer[32768];
            [self updateStatus:@"Receiving"];
            // Pull some data off the network.
            bytesRead = [self.networkStream read:buffer maxLength:sizeof(buffer)];
            if (bytesRead == -1) {
                [self stopReceiveWithStatus:@"Network read error"];
            } else if (bytesRead == 0) {//Send斷線
                [self stopReceiveWithStatus:nil];
            } else {
                NSInteger   bytesWritten;
                NSInteger   bytesWrittenSoFar;
                // Write to the file.
                bytesWrittenSoFar = 0;
                do {
                    //fileStream ->Output Stream
                    bytesWritten = [self.fileStream write:&buffer[bytesWrittenSoFar] maxLength:bytesRead - bytesWrittenSoFar];
                    assert(bytesWritten != 0);
                    if (bytesWritten == -1) {
                        [self stopReceiveWithStatus:@"File write error"];
                        break;
                    } else {
                        bytesWrittenSoFar += bytesWritten;
                    }
                } while (bytesWrittenSoFar != bytesRead);
            }
        } break;
        case NSStreamEventHasSpaceAvailable: {
            assert(NO);     // should never happen for the output stream
        } break;
        case NSStreamEventErrorOccurred: {
            [self stopReceiveWithStatus:@"Stream open error"];
        } break;
        case NSStreamEventEndEncountered: {
            // ignore
        } break;
        default: {
            assert(NO);
        } break;
    }
}


- (void)serverDidStartOnPort:(NSUInteger)port{
    //不要給奇怪的port不然會當掉
    assert( (port != 0) && (port < 65536) );
    [self.startOrStopButton setTitle:@"Stop" forState:UIControlStateNormal];
    self.tabBarItem.image = [UIImage imageNamed:@"receiveserverOn.png"];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
