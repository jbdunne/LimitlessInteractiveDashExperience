//
//  IpadViewController.m
//  IPG_osx_ios
//
//  Created by Gene Han on 3/31/15.
//  Copyright (c) 2015 ipg. All rights reserved.
//

#import "IPGProcotol.h"

#import "IpadViewController.h"

@interface IpadViewController () {
    __weak PTChannel *serverChannel_;
    __weak PTChannel *peerChannel_;
}
@end

@implementation IpadViewController

- (void)viewDidLoad {
    [super viewDidLoad];


    // Create a new channel that is listening on our IPv4 port
    PTChannel *channel = [PTChannel channelWithDelegate:self];
    [channel listenOnPort:PTProtocolIPv4PortNumber IPv4Address:INADDR_LOOPBACK callback:^(NSError *error) {
        if (error) {
            [self appendOutputMessage:[NSString stringWithFormat:@"Failed to listen on 127.0.0.1:%d: %@", PTProtocolIPv4PortNumber, error]];
        } else {
            [self appendOutputMessage:[NSString stringWithFormat:@"Listening on 127.0.0.1:%d", PTProtocolIPv4PortNumber]];
            serverChannel_ = channel;
        }
    }];
}

- (void)viewDidUnload {
    if (serverChannel_) {
        [serverChannel_ close];
    }
    [super viewDidUnload];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return interfaceOrientation == UIInterfaceOrientationPortrait;
}


- (void)sendMessage:(NSString*)message {
    if (peerChannel_) {
        dispatch_data_t payload = PTTextDispatchDataWithString(message);
        [peerChannel_ sendFrameOfType:PTFrameTypeTextMessage tag:PTFrameNoTag withPayload:payload callback:^(NSError *error) {
            if (error) {
                NSLog(@"Failed to send message: %@", error);
            }
        }];
        [self appendOutputMessage:[NSString stringWithFormat:@"[you]: %@", message]];
    } else {
        [self appendOutputMessage:@"Can not send message — not connected"];
    }
}

- (void)appendOutputMessage:(NSString*)message {
    NSLog(@">> %@", message);
  /*
    NSString *text = self.outputTextView.text;
    if (text.length == 0) {
        self.outputTextView.text = [text stringByAppendingString:message];
    } else {
        self.outputTextView.text = [text stringByAppendingFormat:@"\n%@", message];
        [self.outputTextView scrollRangeToVisible:NSMakeRange(self.outputTextView.text.length, 0)];
    }
   */
}


#pragma mark - Communicating

- (void)sendDeviceInfo {
    if (!peerChannel_) {
        return;
    }
    
    NSLog(@"Sending device info over %@", peerChannel_);
    
    UIScreen *screen = [UIScreen mainScreen];
    CGSize screenSize = screen.bounds.size;
    NSDictionary *screenSizeDict = (__bridge_transfer NSDictionary*)CGSizeCreateDictionaryRepresentation(screenSize);
    UIDevice *device = [UIDevice currentDevice];
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
                          device.localizedModel, @"localizedModel",
                          [NSNumber numberWithBool:device.multitaskingSupported], @"multitaskingSupported",
                          device.name, @"name",
                          (UIDeviceOrientationIsLandscape(device.orientation) ? @"landscape" : @"portrait"), @"orientation",
                          device.systemName, @"systemName",
                          device.systemVersion, @"systemVersion",
                          screenSizeDict, @"screenSize",
                          [NSNumber numberWithDouble:screen.scale], @"screenScale",
                          nil];
    dispatch_data_t payload = [info createReferencingDispatchData];
    [peerChannel_ sendFrameOfType:PTFrameTypeDeviceInfo tag:PTFrameNoTag withPayload:payload callback:^(NSError *error) {
        if (error) {
            NSLog(@"Failed to send PTExampleFrameTypeDeviceInfo: %@", error);
        }
    }];
}


#pragma mark - PTChannelDelegate

// Invoked to accept an incoming frame on a channel. Reply NO ignore the
// incoming frame. If not implemented by the delegate, all frames are accepted.
- (BOOL)ioFrameChannel:(PTChannel*)channel shouldAcceptFrameOfType:(uint32_t)type tag:(uint32_t)tag payloadSize:(uint32_t)payloadSize {
    if (channel != peerChannel_) {
        // A previous channel that has been canceled but not yet ended. Ignore.
        return NO;
    } else if (type != PTFrameTypeTextMessage && type != PTFrameTypePing) {
        NSLog(@"Unexpected frame of type %u", type);
        [channel close];
        return NO;
    } else {
        return YES;
    }
}

// Invoked when a new frame has arrived on a channel.
- (void)ioFrameChannel:(PTChannel*)channel didReceiveFrameOfType:(uint32_t)type tag:(uint32_t)tag payload:(PTData*)payload {
    //NSLog(@"didReceiveFrameOfType: %u, %u, %@", type, tag, payload);
    if (type == PTFrameTypeTextMessage) {
        PTTextFrame *textFrame = (PTTextFrame*)payload.data;
        textFrame->length = ntohl(textFrame->length);
        NSString *message = [[NSString alloc] initWithBytes:textFrame->utf8text length:textFrame->length encoding:NSUTF8StringEncoding];
        [self appendOutputMessage:[NSString stringWithFormat:@"[%@]: %@", channel.userInfo, message]];
    } else if (type == PTFrameTypePing && peerChannel_) {
        [peerChannel_ sendFrameOfType:PTFrameTypePong tag:tag withPayload:nil callback:nil];
    }
}

// Invoked when the channel closed. If it closed because of an error, *error* is
// a non-nil NSError object.
- (void)ioFrameChannel:(PTChannel*)channel didEndWithError:(NSError*)error {
    if (error) {
        [self appendOutputMessage:[NSString stringWithFormat:@"%@ ended with error: %@", channel, error]];
    } else {
        [self appendOutputMessage:[NSString stringWithFormat:@"Disconnected from %@", channel.userInfo]];
    }
}

// For listening channels, this method is invoked when a new connection has been
// accepted.
- (void)ioFrameChannel:(PTChannel*)channel didAcceptConnection:(PTChannel*)otherChannel fromAddress:(PTAddress*)address {
    // Cancel any other connection. We are FIFO, so the last connection
    // established will cancel any previous connection and "take its place".
    if (peerChannel_) {
        [peerChannel_ cancel];
    }
    
    // Weak pointer to current connection. Connection objects live by themselves
    // (owned by its parent dispatch queue) until they are closed.
    peerChannel_ = otherChannel;
    peerChannel_.userInfo = address;
    [self appendOutputMessage:[NSString stringWithFormat:@"Connected to %@", address]];
    
    // Send some information about ourselves to the other end
    [self sendDeviceInfo];
}


@end
