//
//  AudioStreamPlayer.m
//  AACStreamPlayer
//
//  Created by annidyfeng on 15/11/19.
//  Copyright © 2015年 annidyfeng. All rights reserved.
//

#import "AudioStreamPlayer.h"

@interface AudioStreamPlayer(private)
- (void)_openAudioFileStream;
- (void)_closeAudioFileStream;

- (void)_interruptionListener:(UInt32)inInterruption;

- (void)_audioQueueOutputCallback:(AudioQueueRef)aAudioQueue audioQueueBuffer:(AudioQueueBufferRef)aAudioBuffer;

- (void)_propertyListenerCallback:(AudioFileStreamID)inAudioFileStream
        audioFileStreamPropertyId:(AudioFileStreamPropertyID)inPropertyID
                          ioFlags:(UInt32*)ioFlags;

- (void)_packetsCallback:(UInt32)inNumberBytes numberPackets:(UInt32)inNumberPackets
               inputData:(const void *)inInputData audioStreamPacketDescription:(AudioStreamPacketDescription*)inPacketDescription;

- (void)_enqueueBuffer;
@end

static void _interruptionListener(void *inUserData, UInt32 inInterruption)
{
    [(__bridge AudioStreamPlayer*)inUserData _interruptionListener:(UInt32)inInterruption];
}

static void _audio_queue_output_callback(void *userData, AudioQueueRef aAudioQueue, AudioQueueBufferRef aAudioBuffer)
{
    [(__bridge AudioStreamPlayer*)userData _audioQueueOutputCallback:aAudioQueue audioQueueBuffer:aAudioBuffer];
}

static void _property_Listener_callback(void *inClientData, AudioFileStreamID inAudioFileStream,
                                        AudioFileStreamPropertyID inPropertyID, UInt32 *ioFlags)
{
    [(__bridge AudioStreamPlayer*)inClientData _propertyListenerCallback:inAudioFileStream
                                      audioFileStreamPropertyId:inPropertyID
                                                        ioFlags:ioFlags];
}

static void _packets_proc(void *inClientData, UInt32 inNumberBytes, UInt32 inNumberPackets,
                          const void *inInputData, AudioStreamPacketDescription *inPacketDescription)
{
    [(__bridge AudioStreamPlayer*)inClientData _packetsCallback:inNumberBytes
                                                 numberPackets:inNumberPackets
                                                     inputData:inInputData
                                  audioStreamPacketDescription:inPacketDescription];
}

static BOOL active = NO, buffering = NO;

@implementation AudioStreamPlayer

- (id)initWithDelegate:(id<AudioStreamPlayerDelegate>)aDelegate bufferSize:(UInt32)size
{
    if((self = [super init])) {
        _delegate = aDelegate;
        
        bufferSize = AUDIOBUFFER_SIZE;
        bufferCount = size / bufferSize;
        _volume = 1.0f;
        
        if(bufferCount < 3)
            bufferCount = 3;
    }
    return self;
}

- (void)setVolume:(Float32)volume
{
    _volume = volume;
    if(audioQueue) {
        AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, volume);
    }
}

- (UInt32)calculateBufferSizePerTime:(NSTimeInterval)interval
{
    UInt32 maxPacketSize = 0;
    Float64 numPacketPerTime = 0.0;
    
    UInt32 dataSize = sizeof(maxPacketSize);
    AudioFileStreamGetProperty(audioStreamId, kAudioFileStreamProperty_PacketSizeUpperBound,
                               &dataSize, &maxPacketSize);
    
    numPacketPerTime = audioBasicDesc.mSampleRate / audioBasicDesc.mFramesPerPacket;
    return numPacketPerTime * maxPacketSize * interval;
}


- (void)_propertyListenerCallback:(AudioFileStreamID)inAudioFileStream
        audioFileStreamPropertyId:(AudioFileStreamPropertyID)inPropertyID
                          ioFlags:(UInt32*)ioFlags
{
    OSStatus oStatus = 0;
    
    NSLog(@"found property '%c%c%c%c'\n",
         (inPropertyID>>24)&255,
         (inPropertyID>>16)&255,
         (inPropertyID>>8)&255,
         inPropertyID&255
         );
    
    if (kAudioFileStreamProperty_ReadyToProducePackets) {
        UInt32 dataSize = sizeof(audioBasicDesc);
        AudioFileStreamGetProperty(inAudioFileStream, kAudioFileStreamProperty_DataFormat, &dataSize, &audioBasicDesc);
        
        oStatus = AudioQueueNewOutput(&audioBasicDesc, _audio_queue_output_callback, (__bridge void *)(self),
                                      NULL, NULL, 0, &audioQueue);
        if(oStatus)
            NSLog(@"failed AudioQueueNewOutput : %d", oStatus);
        
        //bufferSize = AUDIOBUFFER_SIZE;
        targetBufferIndex = 0;
        fillBufferSize = 0;
        fillPacketDescIndex = 0;
        fillQueueBufferCount = 0;
        
        for(int i = 0; i < bufferCount; i++) {
            oStatus = AudioQueueAllocateBuffer(audioQueue, bufferSize, &audioBuffers[i]);
            useBuffer[i] = NO;
        }
    }
}

- (void)_packetsCallback:(UInt32)inNumberBytes numberPackets:(UInt32)inNumberPackets
               inputData:(const void *)inInputData audioStreamPacketDescription:(AudioStreamPacketDescription*)inPacketDescription
{
    for(int i = 0; i < inNumberPackets; i++) {
        SInt64 packetOffset = inPacketDescription[i].mStartOffset;
        SInt64 packetSize   = inPacketDescription[i].mDataByteSize;
        
        size_t remainCount = bufferSize - fillBufferSize;
        if(remainCount < packetSize)
            [self _enqueueBuffer];
        
        AudioQueueBufferRef buffer = audioBuffers[targetBufferIndex];
        memcpy((uint8_t*)buffer->mAudioData + fillBufferSize,
               (uint8_t*)inInputData + packetOffset, packetSize);
        packetDescs[fillPacketDescIndex] = inPacketDescription[i];
        packetDescs[fillPacketDescIndex].mStartOffset = fillBufferSize;
        fillBufferSize += packetSize;
        fillPacketDescIndex++;
        
        size_t remainDescCount = PACKET_DESC_COUNT - fillPacketDescIndex;
        if(remainDescCount == 0) {
            //NSLog(@"packet remain is zero.");
            [self _enqueueBuffer];
        }
    }
}

- (void)_enqueueBuffer
{
    OSStatus oStatus;
    
    NSLog(@"enqeueBuffer : %d", targetBufferIndex);
    
    useBuffer[targetBufferIndex] = YES;
    fillQueueBufferCount++;
    
    AudioQueueBufferRef buffer = audioBuffers[targetBufferIndex];
    buffer->mAudioDataByteSize = fillBufferSize;
    
    oStatus = AudioQueueEnqueueBuffer(audioQueue, buffer, fillPacketDescIndex, packetDescs);
    if(oStatus)
        NSLog(@"failed AudioQueueEnqueueBuffer : %d", oStatus);
    
    if(buffering && fillQueueBufferCount == bufferCount) {
        // set volume
        AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, _volume);
        
        oStatus = AudioQueueStart(audioQueue, NULL);
        if(oStatus)
            NSLog(@"failed AudioQueueStart : %d", oStatus);
        buffering = NO;
        NSLog(@"AudioStreamPlayer play start.");
        
        if(_delegate && [_delegate respondsToSelector:@selector(audioStreamPlayerDidPlay:)]) {
            [(NSObject *)_delegate performSelector:@selector(audioStreamPlayerDidPlay:)
                             onThread:[NSThread mainThread]
                           withObject:self
                        waitUntilDone:NO];
        }
    }
    
    if(++targetBufferIndex >= bufferCount)
        targetBufferIndex = 0;
    fillBufferSize = 0;
    fillPacketDescIndex = 0;
    
    NSLog(@"next fill buffer : %d", targetBufferIndex);
    
    while(useBuffer[targetBufferIndex] && active)
        [NSThread sleepForTimeInterval:0.1];
}

- (int)findAudioQueueBuffer:(AudioQueueBufferRef)inAudioBuffer
{
    for(int i = 0; i < bufferCount; i++) {
        if(inAudioBuffer == audioBuffers[i])
            return i;
    }
    return -1;
}

- (void)_audioQueueOutputCallback:(AudioQueueRef)inAudioQueue audioQueueBuffer:(AudioQueueBufferRef)inAudioBuffer
{
    int index = [self findAudioQueueBuffer:inAudioBuffer];
    NSLog(@"unUse. : %d", index);
    
    useBuffer[index] = NO;
    fillQueueBufferCount--;
    
    NSLog(@"fillQueueBufferCount : %d", fillQueueBufferCount);
    
    if(fillQueueBufferCount < 1) {
        NSLog(@"empty buffer.");
        
        //AudioQueuePause(audioQueue);
        //buffering = YES;
        
        if(_delegate && [_delegate respondsToSelector:@selector(audioStreamPlayerDidEmptyBuffer:)]) {
            [(NSObject *)_delegate performSelector:@selector(audioStreamPlayerDidEmptyBuffer:)
                             onThread:[NSThread mainThread]
                           withObject:self
                        waitUntilDone:NO];
        }
    }
    
}

- (void)_openAudioFileStream
{
    AudioFileStream_PropertyListenerProc listenerProc = _property_Listener_callback;
    AudioFileStream_PacketsProc packetsProc = _packets_proc;
    OSStatus oStatus = 0;
    
    oStatus = AudioFileStreamOpen((__bridge void *)(self), listenerProc, packetsProc, kAudioFileAAC_ADTSType, &audioStreamId);
    if(oStatus)
        NSLog(@"failed AudioFileStreamOpen : %d", oStatus);
}

- (void)_interruptionListener:(UInt32)inInterruption
{
    if(inInterruption == kAudioSessionEndInterruption) {
        AudioSessionSetActive(true);
    } else if(inInterruption == kAudioSessionBeginInterruption) {
        
    }
}

- (void)play
{
    if(active)
        return;
    
    active = YES;
    buffering = YES;
    
    [self _openAudioFileStream];
    
    [NSThread detachNewThreadSelector:@selector(run:) toTarget:self withObject:self];
}

- (void)stop
{
    if(!active)
        return;
    
    active = NO;
    AudioQueueStop(audioQueue, true);
}

- (void)dispose
{
    AudioQueueStop(audioQueue, true);
    active = NO;
    
    for(int i=0; i<bufferCount; i++) {
        AudioQueueFreeBuffer(audioQueue, audioBuffers[i]);
        audioBuffers[i] = NULL;
    }
    NSLog(@"AudioQueueDispose");
    AudioQueueDispose(audioQueue, true);
    
    NSLog(@"AudoFileStreamClose");
    AudioFileStreamClose(audioStreamId);
}

- (void)stream:(NSStream *)stream handleEvent:(NSStreamEvent)eventCode
{
    switch(eventCode) {
        case NSStreamEventOpenCompleted: {
            NSLog(@"NSStreamEventOpenCompleted");
        }
            break;
        case NSStreamEventErrorOccurred: {
            NSLog(@"NSStreamEventErrorOccurred");
        }
            break;
        case NSStreamEventHasBytesAvailable: {
            NSLog(@"NSStreamEventHasBytesAvailable");
            if (stream == _inputStream) {
                uint8_t buf[1024];
                NSUInteger len = [_inputStream read:buf maxLength:sizeof(buf)];
                if(len) {
                    NSLog(@"read %lu", len);
                    AudioFileStreamParseBytes(audioStreamId, (UInt32)len, (const void*)buf, 0);
                } else {
                    NSLog(@"no buffer!");
                }
            }
        }
            break;
        case NSStreamEventEndEncountered: {
            NSLog(@"NSStreamEventEndEncountered");
            [self dispose];
        }
            break;
        default:
            break;
            // continued
    }
}

- (void)run:(id)param
{
    NSLog(@"AudioStreamPlayer start");
    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
    
    [_inputStream setDelegate:self];
    [_inputStream scheduleInRunLoop:runLoop forMode:NSDefaultRunLoopMode];
    [_inputStream open];
    
    
    [runLoop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode]; // adding some input source, that is required for runLoop to runing
    while (active && [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantPast]]); // starting infinite loop which can be stopped by changing the shouldKeepRunning's value
    
    [_inputStream close];
    
    if(_delegate && [_delegate respondsToSelector:@selector(audioStreamPlayerDidStop:)]) {
        [(NSObject *)_delegate performSelector:@selector(audioStreamPlayerDidStop:)
                                      onThread:[NSThread mainThread]
                                    withObject:self
                                 waitUntilDone:NO];
    }
    NSLog(@"run end");
}

@end
