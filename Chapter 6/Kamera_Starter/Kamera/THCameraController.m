//
//  MIT License
//
//  Copyright (c) 2014 Bob McCune http://bobmccune.com/
//  Copyright (c) 2014 TapHarmonic, LLC http://tapharmonic.com/
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import "THCameraController.h"
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import "NSFileManager+THAdditions.h"

NSString *const THThumbnailCreatedNotification = @"THThumbnailCreated";

@interface THCameraController () <AVCaptureFileOutputRecordingDelegate>

@property (strong, nonatomic) dispatch_queue_t videoQueue;
@property (strong, nonatomic) AVCaptureSession *captureSession;
@property (weak, nonatomic) AVCaptureDeviceInput *activeVideoInput;
@property (strong, nonatomic) AVCaptureStillImageOutput *imageOutput;
@property (strong, nonatomic) AVCaptureMovieFileOutput *movieOutput;
@property (strong, nonatomic) NSURL *outputURL;

@end

@implementation THCameraController

- (BOOL)setupSession:(NSError **)error {

    // Listing 6.4
    self.captureSession = [[AVCaptureSession alloc] init];
    self.captureSession.sessionPreset = AVCaptureSessionPresetHigh;
    
    // Set up the default video input
    AVCaptureDevice* videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDeviceInput* cameraDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:error];
    if (cameraDeviceInput) {
        if ([self.captureSession canAddInput:cameraDeviceInput]) {
            [self.captureSession addInput:cameraDeviceInput];
            self.activeVideoInput = cameraDeviceInput;
        }
    }else {
        return NO;
    }
    
    
    // Set up the default audio
    AVCaptureDevice* audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    AVCaptureDeviceInput* audioDeviceInput = [AVCaptureDeviceInput deviceInputWithDevice:audioDevice error:error];
    if (audioDeviceInput) {
        if ([self.captureSession canAddInput:audioDeviceInput]) {
            [self.captureSession addInput:audioDeviceInput];
        }
    } else {
        return NO;
    }
    
    // Set up the still image output
    self.imageOutput = [[AVCaptureStillImageOutput alloc] init];
    self.imageOutput.outputSettings = @{AVVideoCodecKey:AVVideoCodecJPEG};
    if ([self.captureSession canAddOutput:self.imageOutput]) {
        [self.captureSession addOutput:self.imageOutput];
    }
    
    
    // Set up the movie output
    self.movieOutput = [[AVCaptureMovieFileOutput alloc] init];
    if ([self.captureSession canAddOutput:self.movieOutput]) {
        [self.captureSession addOutput:self.movieOutput];
    }
    
    self.videoQueue = dispatch_queue_create("vn.snapbuck.SnapbuckMobile", NULL);
    return YES;
}

- (void)startSession {

    // Listing 6.5
    if (![self.captureSession isRunning]) {
        dispatch_async(self.videoQueue, ^{
            [self.captureSession startRunning];
        });
    }
}

- (void)stopSession {

    // Listing 6.5
    if ([self.captureSession isRunning]) {
        dispatch_async(self.videoQueue, ^{
            [self.captureSession stopRunning];
        });
    }
}

#pragma mark - Device Configuration

- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition)position {

    // Listing 6.6
    NSArray* allDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for (AVCaptureDevice* device in allDevices) {
        if (device.position == position) {
            return device;
        }
    }
    return nil;
}

- (AVCaptureDevice *)activeCamera {

    // Listing 6.6
    
    return [self.activeVideoInput device];
}

- (AVCaptureDevice *)inactiveCamera {

    // Listing 6.6
    AVCaptureDevice* inactiveDevice = nil;
    if (self.cameraCount > 1) {
        AVCaptureDevicePosition activePostion = [self.activeVideoInput.device position];
        if (activePostion == AVCaptureDevicePositionBack) {
            inactiveDevice = [self cameraWithPosition:AVCaptureDevicePositionFront];
        } else if (activePostion == AVCaptureDevicePositionFront){
            inactiveDevice = [self cameraWithPosition:AVCaptureDevicePositionBack];
        }
    }
    return inactiveDevice;
}

- (BOOL)canSwitchCameras {

    // Listing 6.6
    
    return (self.cameraCount > 1);
}

- (NSUInteger)cameraCount {

    // Listing 6.6
    
    return [[AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo] count];
}

- (BOOL)switchCameras {

    // Listing 6.7
    if ([self canSwitchCameras] == NO) {
        return NO;
    }
    
    AVCaptureDevice* deviceToSwitchTo = [self inactiveCamera];
    NSError* error = nil;
    AVCaptureDeviceInput* inputToSwitchTo = [AVCaptureDeviceInput deviceInputWithDevice:deviceToSwitchTo error:&error];
    if (inputToSwitchTo != nil) {
        [self.captureSession beginConfiguration];
        [self.captureSession removeInput:self.activeVideoInput];
        
        if ([self.captureSession canAddInput:inputToSwitchTo]) {
            [self.captureSession addInput:inputToSwitchTo];
            self.activeVideoInput = inputToSwitchTo;
        }else {
            [self.captureSession addInput:self.activeVideoInput];
        }
        [self.captureSession commitConfiguration];
    } else {
        [self.delegate deviceConfigurationFailedWithError:error];
        return NO;
    }
    
    return YES;
}

#pragma mark - Focus Methods

- (BOOL)cameraSupportsTapToFocus {
    
    // Listing 6.8
    
    return [[self activeCamera] isFocusPointOfInterestSupported];
}

- (void)focusAtPoint:(CGPoint)point {
    
    // Listing 6.8
    AVCaptureDevice* activeDevice = [self activeCamera];
    if ([activeDevice isFocusPointOfInterestSupported] && [activeDevice isFocusModeSupported:AVCaptureFocusModeAutoFocus]) {
        NSError* error = nil;
        if ([activeDevice lockForConfiguration:&error]) {
            [activeDevice setFocusMode:AVCaptureFocusModeAutoFocus];
            [activeDevice setFocusPointOfInterest:point];
            [activeDevice unlockForConfiguration];
        } else {
            [self.delegate deviceConfigurationFailedWithError:error];
        }
        
    }
    
}

#pragma mark - Exposure Methods

- (BOOL)cameraSupportsTapToExpose {
 
    // Listing 6.9
    
    return [[self activeCamera] isExposurePointOfInterestSupported];
}

static const NSString* THCameraAdjustingExposureContext;
- (void)exposeAtPoint:(CGPoint)point {

    // Listing 6.9
    AVCaptureDevice* activeCameraDevice = [self activeCamera];
    AVCaptureExposureMode exposureMode = AVCaptureExposureModeAutoExpose;
    if ([activeCameraDevice isExposurePointOfInterestSupported] && [activeCameraDevice isExposureModeSupported:exposureMode]) {
        NSError* error = nil;
        if ([activeCameraDevice lockForConfiguration:&error]) {
            [activeCameraDevice setExposureMode:exposureMode];
            [activeCameraDevice setExposurePointOfInterest:point];
            
            if ([activeCameraDevice isExposureModeSupported:AVCaptureExposureModeLocked]) {
                [activeCameraDevice addObserver:self
                                     forKeyPath:@"adjustingExposure"
                                        options:NSKeyValueObservingOptionNew
                                        context:&THCameraAdjustingExposureContext];
            }
            [activeCameraDevice unlockForConfiguration];
        }else {
            [self.delegate deviceConfigurationFailedWithError:error];
        }
    }

}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context {

    // Listing 6.9
    if (context == &THCameraAdjustingExposureContext) {
        AVCaptureDevice* cameraDevice = (AVCaptureDevice*)object;
        if ([cameraDevice isExposureModeSupported:AVCaptureExposureModeLocked]) {
            [object removeObserver:self
                        forKeyPath:@"adjustingExposure"
                           context:&THCameraAdjustingExposureContext];
            dispatch_async(dispatch_get_main_queue(), ^{
                NSError* error = nil;
                if ([cameraDevice lockForConfiguration:&error]) {
                    [cameraDevice setExposureMode:AVCaptureExposureModeLocked];
                    [cameraDevice unlockForConfiguration];
                } else{
                    [self.delegate deviceConfigurationFailedWithError:error];
                }
            });
        }
    }else {
        [super observeValueForKeyPath:keyPath
                             ofObject:object
                               change:change
                              context:context];
    }

}

- (void)resetFocusAndExposureModes {

    // Listing 6.10
    AVCaptureDevice* cameraDevice = [self activeCamera];
    AVCaptureExposureMode exposureMode = AVCaptureExposureModeContinuousAutoExposure;
    AVCaptureFocusMode focusMode = AVCaptureFocusModeContinuousAutoFocus;
    BOOL canResetExposure = [cameraDevice isExposurePointOfInterestSupported] && [cameraDevice isExposureModeSupported:exposureMode];
    BOOL canResetFocus = [cameraDevice isFocusPointOfInterestSupported] && [cameraDevice isFocusModeSupported:focusMode];

    NSError* error = nil;
    if ([cameraDevice lockForConfiguration:&error]){
        CGPoint centerPoint = CGPointMake(.5, .5);
    
        if (canResetExposure) {
            [cameraDevice setExposureMode:exposureMode];
            [cameraDevice setExposurePointOfInterest:centerPoint];
        }
        
        if (canResetFocus) {
            [cameraDevice setFocusMode:focusMode];
            [cameraDevice setFocusPointOfInterest:centerPoint];
        }
        
        [cameraDevice unlockForConfiguration];
    }else{
        [self.delegate deviceConfigurationFailedWithError:error];
    }

}



#pragma mark - Flash and Torch Modes

- (BOOL)cameraHasFlash {

    // Listing 6.11
    
    return [[self activeCamera] hasFlash];
}

- (AVCaptureFlashMode)flashMode {

    // Listing 6.11
    
    return [[self activeCamera] flashMode];
}

- (void)setFlashMode:(AVCaptureFlashMode)flashMode {

    // Listing 6.11
    AVCaptureDevice* activeCameraDevice = [self activeCamera];
    NSError* error = nil;
    if ([activeCameraDevice lockForConfiguration:&error]) {
        if ([activeCameraDevice hasFlash] && [activeCameraDevice isFlashModeSupported:flashMode]) {
            [activeCameraDevice setFlashMode:flashMode];
        }
        [activeCameraDevice unlockForConfiguration];
    } else {
        [self.delegate deviceConfigurationFailedWithError:error];
    }

}

- (BOOL)cameraHasTorch {

    // Listing 6.11
    
    return [[self activeCamera] hasTorch];
}

- (AVCaptureTorchMode)torchMode {

    // Listing 6.11
    
    return [[self activeCamera] torchMode];
}

- (void)setTorchMode:(AVCaptureTorchMode)torchMode {

    // Listing 6.11
    AVCaptureDevice* activeCamera = [self activeCamera];
    if ([activeCamera hasTorch] && [activeCamera isTorchModeSupported:torchMode]) {
        NSError* error = nil;
        if ([activeCamera lockForConfiguration:&error]) {
            [activeCamera setTorchMode:torchMode];
            [activeCamera unlockForConfiguration];
        } else {
            [self.delegate deviceConfigurationFailedWithError:error];
        }
    }
}


#pragma mark - Image Capture Methods

- (void)captureStillImage {

    // Listing 6.12

}

- (AVCaptureVideoOrientation)currentVideoOrientation {
    
    // Listing 6.12
    
    // Listing 6.13
    
    return 0;
}


- (void)writeImageToAssetsLibrary:(UIImage *)image {

    // Listing 6.13
    
}

- (void)postThumbnailNotifification:(UIImage *)image {

    // Listing 6.13
    
}

#pragma mark - Video Capture Methods

- (BOOL)isRecording {

    // Listing 6.14
    
    return NO;
}

- (void)startRecording {

    // Listing 6.14

}

- (CMTime)recordedDuration {
    return self.movieOutput.recordedDuration;
}

- (NSURL *)uniqueURL {


    // Listing 6.14
    
    return nil;
}

- (void)stopRecording {

    // Listing 6.14
}

#pragma mark - AVCaptureFileOutputRecordingDelegate

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL
      fromConnections:(NSArray *)connections
                error:(NSError *)error {

    // Listing 6.15

}

- (void)writeVideoToAssetsLibrary:(NSURL *)videoURL {

    // Listing 6.15
    
}

- (void)generateThumbnailForVideoAtURL:(NSURL *)videoURL {

    // Listing 6.15
    
}


@end

