//
//  ViewController.h
//  OBSTwitter
//
//  Created by Adam Bemowski on 10/30/12.
//  Copyright (c) 2012 OBS. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "TSStream.h"
#import "TSModelParser.h"
#import <Accounts/Accounts.h>
#import <Twitter/Twitter.h>
#import <dispatch/dispatch.h>
#import <CoreData/CoreData.h>
#import "Tweet.h"

@interface ViewController : UIViewController <UIActionSheetDelegate, TSStreamDelegate,UITableViewDataSource,UITableViewDelegate> {
    
    ACAccountStore* accountStore;
    NSArray* accounts;
    ACAccount* account;
    NSMutableArray* tweets;
    IBOutlet UITableView *tableViewTweets;
    TSStream* stream;
    NSTimer *myTimer;
    NSString *since_id;
    dispatch_queue_t backgroundQueue;
    IBOutlet UIButton *buttonChangeAccount;
    
    NSManagedObjectContext *managedObjectContext;
}

@property (nonatomic, retain) ACAccountStore* accountStore;
@property (nonatomic, retain) NSArray* accounts;
@property (nonatomic, retain) ACAccount* account;
@property (nonatomic, retain) NSMutableArray* tweets;
@property (nonatomic, retain) IBOutlet UITableView *tableViewTweets;
@property (nonatomic, retain) TSStream* stream;
@property (nonatomic, retain) NSTimer *myTimer;
@property (nonatomic,retain) NSString *since_id;
@property (nonatomic,assign) dispatch_queue_t backgroundQueue;
@property (nonatomic,retain) IBOutlet UIButton *buttonChangeAccount;

@property (nonatomic, retain) NSManagedObjectContext *managedObjectContext;

-(IBAction)authenticateUser:(id)sender;
-(IBAction)postTweet:(id)sender;

@end
