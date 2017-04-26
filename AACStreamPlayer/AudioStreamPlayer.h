//
//  AudioStreamPlayer.h
//  AACStreamPlayer
//
//  Created by annidyfeng on 15/11/19.
//  Copyright © 2015年 annidyfeng. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#define AUDIOBUFFER_MAXCOUNT 256
#define AUDIOBUFFER_SIZE  4096
#define PACKET_DESC_COUNT 160

@class AudioStreamPlayer;

@protocol AudioStreamPlayerDelegate<NSObject>

- (void)audioStreamPlayerDidPlay:(AudioStreamPlayer*)player;
- (void)audioStreamPlayerDidStop:(AudioStreamPlayer*)player;
- (void)audioStreamPlayerDidEmptyBuffer:(AudioStreamPlayer*)player;

@end

@interface AudioStreamPlayer : NSObject<NSStreamDelegate> {
    
    AudioFileStreamID audioStreamId;
    AudioStreamBasicDescription audioBasicDesc;
    AudioQueueRef audioQueue;
    
    UInt32 bufferCount;
    UInt32 bufferSize;
    AudioQueueBufferRef audioBuffers[AUDIOBUFFER_MAXCOUNT];
    BOOL useBuffer[AUDIOBUFFER_MAXCOUNT];
    int targetBufferIndex;
    UInt32 fillBufferSize;
    UInt32 fillQueueBufferCount;
    
    AudioStreamPacketDescription packetDescs[PACKET_DESC_COUNT];
    UInt32 fillPacketDescIndex;
}

@property (nonatomic, assign) id<AudioStreamPlayerDelegate> delegate;
@property (nonatomic, strong) NSInputStream *inputStream;

@property (nonatomic, readwrite) Float32 volume;

- (id)initWithDelegate:(id<AudioStreamPlayerDelegate>)aDelegate bufferSize:(UInt32)size;
- (void)play;
- (void)stop;

@end


