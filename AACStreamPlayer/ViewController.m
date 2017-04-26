//
//  ViewController.m
//  AACStreamPlayer
//
//  Created by annidyfeng on 15/11/19.
//  Copyright © 2015年 annidyfeng. All rights reserved.
//

#import "ViewController.h"

#define TAG_PLAY 0
#define TAG_STOP 1

@interface ViewController ()

@property UITextField   *urlTextFeild;
@property UIButton      *playOrStopButton;
@property AudioStreamPlayer *streamPlayer;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    _urlTextFeild = [[UITextField alloc] initWithFrame:CGRectMake(8, 120, CGRectGetWidth(self.view.frame)-16, 30)];
    _urlTextFeild.borderStyle = UITextBorderStyleRoundedRect;
    _urlTextFeild.text = @"tcp://127.0.0.1:9999";
    [self.view addSubview:_urlTextFeild];
    
    _playOrStopButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _playOrStopButton.frame = CGRectMake(0, 150, CGRectGetWidth(self.view.frame), 30);
    [_playOrStopButton setTitle:@"播放" forState:UIControlStateNormal];
    [_playOrStopButton addTarget:self action:@selector(btnClicked:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_playOrStopButton];
    self.view.backgroundColor = [UIColor lightGrayColor];
    
    _streamPlayer = [[AudioStreamPlayer alloc] initWithDelegate:self bufferSize:4096];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (void)btnClicked:(id)sender
{
    if (_playOrStopButton.tag == TAG_PLAY) {
        
        CFReadStreamRef readStream = NULL;
        CFWriteStreamRef writeStream = NULL;
        
        NSURL *url = [NSURL URLWithString:_urlTextFeild.text];
        
        CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, (__bridge CFStringRef)[url host], [[url port] intValue], &readStream, &writeStream);
        if(!CFWriteStreamOpen(writeStream)) {
            NSLog(@"Error, writeStream not open");
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"错误"
                                                            message:@"打开链接失败"
                                                           delegate:nil
                                                  cancelButtonTitle:@"确定"
                                                  otherButtonTitles:nil, nil];
            [alert show];
            return;
        }
        
        if (readStream) {
            _streamPlayer.inputStream = (__bridge_transfer NSInputStream *)readStream;
            [_streamPlayer play];
        }
        CFWriteStreamClose(writeStream);
        [_playOrStopButton setTitle:@"停止" forState:UIControlStateNormal];
        _playOrStopButton.tag = TAG_STOP;
    } else {
        [_streamPlayer stop];
    }
}

#pragma mark - AudioStreamPlayerDelegate

- (void)audioStreamPlayerDidPlay:(AudioStreamPlayer*)player
{
//    [_playOrStopButton setTitle:@"停止" forState:UIControlStateNormal];
//    _playOrStopButton.tag = TAG_STOP;
}

- (void)audioStreamPlayerDidStop:(AudioStreamPlayer*)player
{
    [_playOrStopButton setTitle:@"播放" forState:UIControlStateNormal];
    _playOrStopButton.tag = TAG_PLAY;
}

- (void)audioStreamPlayerDidEmptyBuffer:(AudioStreamPlayer*)player
{
    
}
@end
