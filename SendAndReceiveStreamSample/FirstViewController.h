//
//  FirstViewController.h
//  SendAndReceiveStreamSample
//
//  Created by Mac Mini on 13/2/7.
//  Copyright (c) 2013年 E-Lead. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "OverlayViewController.h"

@interface FirstViewController : UIViewController <OverlayViewControllerDelegate,UIGestureRecognizerDelegate,NSStreamDelegate>{
    IBOutlet UIImageView *cameraImageView;
    UIImage *img;
    IBOutlet UIButton *sendBtn;
}

@property (nonatomic, retain) UIImage *img;
@property (nonatomic, retain) UIImageView *cameraImageView;
@property (nonatomic, retain) OverlayViewController *overlayViewController;
@property (nonatomic, retain) NSMutableArray *capturedImages;

- (void)tapTheCameraImage;

- (IBAction)sendStream:(id)sender;

- (void)stopServer:(NSString *)reason;

@end