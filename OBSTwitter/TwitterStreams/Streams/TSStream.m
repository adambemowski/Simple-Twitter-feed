//
//  TSStream.m
//
//  Created by Stuart Hall on 6/03/12.
//  Copyright (c) 2012 Stuart Hall. All rights reserved.
//

#import "TSStream.h"
#import "JSONKit.h"
#import "TSModelParser.h"

#import <Twitter/Twitter.h>
#import <Accounts/Accounts.h>
#import "Tweet.h"

#define MAX_COREDATA_TWEETS 50

@interface TSStream ()

@property (nonatomic, retain) NSURLConnection* connection;
@property (nonatomic, retain) NSTimer* keepAliveTimer;
@property (nonatomic, assign) id<TSStreamDelegate> delegate;
@property (nonatomic, retain) ACAccount* account;
@property (nonatomic, retain) NSMutableDictionary* parameters;
@property (nonatomic, retain) NSString* endpoint;
@property (nonatomic,assign) dispatch_queue_t backgroundQueue;
@property (nonatomic, retain) NSManagedObjectContext *managedObjectContext;

@end

@implementation TSStream

@synthesize connection=_connection;
@synthesize keepAliveTimer=_keepAliveTimer;
@synthesize delegate=_delegate;
@synthesize account=_account;
@synthesize parameters=_parameters;
@synthesize endpoint=_endpoint;
@synthesize backgroundQueue;
@synthesize managedObjectContext;

- (void)dealloc {
    [self.connection cancel];
    self.connection = nil;
    
    [self.keepAliveTimer invalidate];
    self.keepAliveTimer = nil;
    
    self.account = nil;
    self.parameters = nil;
    self.endpoint = nil;
    
    [super dealloc];
}

- (id)initWithEndpoint:(NSString*)endpoint
         andParameters:(NSDictionary*)parameters
            andAccount:(ACAccount*)account
           andDelegate:(id<TSStreamDelegate>)delegate {
    self = [super init];
    if (self) {
        // Save the parameters
        self.delegate = delegate;
        self.account = account;
        self.endpoint = endpoint;
        
        // Use length delimited so we can count the bytes
        self.parameters = [NSMutableDictionary dictionaryWithDictionary:parameters];
        [self.parameters setObject:@"length" forKey:@"delimited"];
        
        backgroundQueue = dispatch_queue_create("com.OBS.OBSTwitter.bgqueue", NULL);
        
        //set the managed object for core data if its not already set
        if (managedObjectContext == nil)
        {
            managedObjectContext = [(AppDelegate *)[[UIApplication sharedApplication] delegate] managedObjectContext];
            NSLog(@"After managedObjectContext: %@", managedObjectContext);
        }
    }
    return self;
}

#pragma mark - Public methods

- (void)start {
    // Our actually request
    TWRequest *request = [[TWRequest alloc]
                          initWithURL:[NSURL URLWithString:self.endpoint]
                          parameters:self.parameters
                          requestMethod:TWRequestMethodGET];
        
    // Set the current account for authentication, or even just rate limit
    [request setAccount:self.account];
    
    [request performRequestWithHandler: ^(NSData *responseData, NSHTTPURLResponse *urlResponse, NSError *error) {
         
         if (!responseData) {
             // inspect the contents of error
             NSLog(@"%@", error);
         }
         else {
             NSError *jsonError;
             NSArray *timeline = [NSJSONSerialization JSONObjectWithData:responseData options:NSJSONReadingMutableLeaves error:&jsonError];
             
             if (timeline) {
                 // at this point, we have an object that we can parse
                 //NSLog(@"%@", timeline);
                 dispatch_async(backgroundQueue, ^(void) {
                     [self processTweetResponse:timeline];
                 });
             }
             else { 
                 // inspect the contents of jsonError
                 if (self.delegate && [self.delegate respondsToSelector:@selector(streamDidReceiveInvalidJson:message:)])
                     [self.delegate streamDidReceiveInvalidJson:self message:[NSString stringWithFormat:@"%@", jsonError]];
             }
         }
     }];
    
//    // Use the signed request to start a connection
//    self.connection = [NSURLConnection connectionWithRequest:request.signedURLRequest
//                                                    delegate:self];
//    
//    // Start the keepalive timer and connection
//    [self resetKeepalive];
//    [self.connection start];
    
    [request release];
}

- (void)processTweetResponse:(NSArray *)tweetsReturned {
    
    //reverse the order of the array
    tweetsReturned = [[tweetsReturned reverseObjectEnumerator] allObjects];
    
    int counter = 0;
    for (NSDictionary *tweetJson in tweetsReturned) {
        [TSModelParser parseJson:tweetJson
                         friends:^(TSFriendsList *model) {
                             NSLog(@"Got friends list");
                         } tweet:^(TSTweet *model) {
                             // Got a new tweet!
                             //NSLog(@"%@",model);
                             [self saveTweetsToCoreData:model];
                             [self purgeTweetsFromCoreData];
                             //make sure to alert the delegate on the main thread since we will be dealing with uikit
                             dispatch_async(dispatch_get_main_queue(), ^(void) {
                                 // Alert the delegate
                                 if (self.delegate && [self.delegate respondsToSelector:@selector(streamDidReceiveMessage:)])
                                     [self.delegate streamDidReceiveMessage:model];
                             });
                         } deleteTweet:^(TSTweet *model) {
                             NSLog(@"Delete Tweet");
                         } follow:^(TSFollow *model) {
                             NSLog(@"@%@ Followed @%@", model.source.screenName, model.target.screenName);
                         } favorite:^(TSFavorite *model) {
                             NSLog(@"@%@ favorited tweet by @%@", model.source.screenName, model.tweet.user.screenName);
                         } unfavorite:^(TSFavorite *model) {
                             NSLog(@"@%@ unfavorited tweet by @%@", model.source.screenName, model.tweet.user.screenName);
                         } unsupported:^(id tweetJson) {
                             NSLog(@"Unsupported : %@", tweetJson);
                         }];
    }
}

- (void)saveTweetsToCoreData:(TSTweet *)tweetToSave {
    // Save to CoreData
    // Step 1: Create Object
    Tweet * newTweet = (Tweet *)[NSEntityDescription insertNewObjectForEntityForName:@"Tweet" inManagedObjectContext:managedObjectContext];
    
    // Step 2: Set Properties
    newTweet.tweetId = tweetToSave.ID;
    newTweet.text = tweetToSave.text;
    newTweet.username = tweetToSave.username;
    
    // Step 3: Save Object
    NSError *error;
    if (![self.managedObjectContext save:&error]) {
        NSLog(@"Unresolved Core Data Save error %@, %@", error, [error userInfo]);
        exit(-1);
    }
}

- (void)purgeTweetsFromCoreData{
    NSLog(@"purging tweets");
    
    //setup the fetch request
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    // define the entity to use
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"Tweet" inManagedObjectContext:self.managedObjectContext];
    [fetchRequest setEntity:entity];
    
    NSSortDescriptor * sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"tweetId" ascending:NO];
    NSArray * sortDescriptors = [[NSArray alloc] initWithObjects:sortDescriptor, nil];
    [fetchRequest setSortDescriptors:sortDescriptors];
    
    NSError *theError;
    NSMutableArray *results = [[self.managedObjectContext executeFetchRequest:fetchRequest error:&theError] mutableCopy];
    if (!results) {
        //serious error restart the app
        NSLog(@"encountered a serious error please restart the app!");
    }
    //display data
    if ([results count] > MAX_COREDATA_TWEETS) {
        for (int i = MAX_COREDATA_TWEETS; i < [results count]; i++) {
            [managedObjectContext deleteObject:[managedObjectContext objectWithID:[[results objectAtIndex:i] objectID]]];
        }
    }
    [fetchRequest release];
}

- (void)stop {
    [self.connection cancel];
    self.connection = nil;
}

#pragma mark - Keep Alive

- (void)resetKeepalive {
    [self.keepAliveTimer invalidate];
    self.keepAliveTimer = [NSTimer scheduledTimerWithTimeInterval:40 
                                                           target:self 
                                                         selector:@selector(onTimeout)
                                                         userInfo:nil
                                                          repeats:NO];
}

- (void)onTimeout {
    // Timeout
    [self stop];
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(streamDidTimeout:)])
        [self.delegate streamDidTimeout:self];
    
    // Try and restart
    [self start];
}

//#pragma mark - NSURLConnectionDelegate
//
//- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
//    int bytesExpected = 0;
//    NSMutableString* message = nil;
//    
//    NSString* response = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
//    for (NSString* part in [response componentsSeparatedByString:@"\r\n"]) {
//        int length = [part intValue];
//        if (length > 0) {
//            // New message
//            message = [NSMutableString string];
//            bytesExpected = length;
//        }
//        else if (bytesExpected > 0 && message) {
//            if (message.length < bytesExpected) {
//                // Append the data
//                [message appendString:part];
//                
//                if (message.length < bytesExpected) {
//                    // Newline counts
//                    [message appendString:@"\r\n"];
//                }
//                
//                if (message.length == bytesExpected) {
//                    // Success!
//                    id json = [message objectFromJSONString];
//                    NSLog(@"json %@",json);
//                    
//                    // Alert the delegate
//                    if (json) { 
//                        if (self.delegate && [self.delegate respondsToSelector:@selector(streamDidReceiveMessage:json:)])
//                            [self.delegate streamDidReceiveMessage:self json:json];
//                        [self resetKeepalive];
//                    }
//                    else  {
//                        if (self.delegate && [self.delegate respondsToSelector:@selector(streamDidReceiveInvalidJson:message:)])
//                            [self.delegate streamDidReceiveInvalidJson:self message:message];
//                    }
//                    
//                    // Reset
//                    message = nil;
//                    bytesExpected = 0;
//                }
//            }
//        }
//        else {
//            // Keep alive
//            [self resetKeepalive];
//        }
//    }
//}
//
//- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
//    if (self.delegate && [self.delegate respondsToSelector:@selector(streamDidFailConnection:)])
//        [self.delegate streamDidFailConnection:self];
//
//}

@end
