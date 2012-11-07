//
//  ViewController.m
//  OBSTwitter
//
//  Created by Adam Bemowski on 10/30/12.
//  Copyright (c) 2012 OBS. All rights reserved.
//

#import "ViewController.h"
#import "NSArray+Enumerable.h"
#import "AppDelegate.h"

#define TIMER_SECONDS 10

@implementation ViewController

@synthesize accountStore;
@synthesize accounts;
@synthesize account;
@synthesize tweets;
@synthesize tableViewTweets;
@synthesize stream;
@synthesize myTimer;
@synthesize since_id;
@synthesize backgroundQueue;
@synthesize managedObjectContext;
@synthesize buttonChangeAccount;

- (void)viewDidLoad
{
    //set the managed object for core data if its not already set
    if (managedObjectContext == nil)
    {
        managedObjectContext = [(AppDelegate *)[[UIApplication sharedApplication] delegate] managedObjectContext];
        NSLog(@"After managedObjectContext: %@", managedObjectContext);
    }
    
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib
    
    backgroundQueue = dispatch_queue_create("com.OBS.OBSTwitter.bgqueue2", NULL);
    
    // Holds the tweet list
    self.tweets = [NSMutableArray array];
}

- (void)viewDidAppear:(BOOL)animated {
    [self loadCoreDataTweets];
    
    buttonChangeAccount.hidden = NO;
    //check to see if we have an index for any twitter account.
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:@"accountIndex"]) {
        //  First, we need to obtain the account instance for the user's Twitter account
        ACAccountStore *store = [[ACAccountStore alloc] init];
        ACAccountType *twitterAccountType =
        [store accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierTwitter];
        //  Request permission from the user to access the available Twitter accounts
        [store requestAccessToAccountsWithType:twitterAccountType
                         withCompletionHandler:^(BOOL granted, NSError *error) {
                             if (!granted) {
                                 // The user rejected your request
                                 NSLog(@"User rejected access to the account.");
                             }
                             else {
                                 // Grab the available accounts
                                 NSArray *twitterAccounts =
                                 [store accountsWithAccountType:twitterAccountType];
                                 
                                 if ([twitterAccounts count] > 0) {
                                     //hide change account button
                                     buttonChangeAccount.hidden = YES;
                                     
                                     // Use the correctly saved account
                                     self.account = [twitterAccounts objectAtIndex:[[defaults objectForKey:@"accountIndex"] intValue]];
                                     
                                     dispatch_async(backgroundQueue, ^(void) {
                                         [self startTweetStream];
                                     });
                                     
                                     //need to run on main thread to validate timer
                                     dispatch_async(dispatch_get_main_queue(), ^(void) {
                                         myTimer = [NSTimer scheduledTimerWithTimeInterval:TIMER_SECONDS target:self selector:@selector(createTweetTimer) userInfo:nil repeats:YES];
                                     });
                                     
                                 }
                             }
                         }];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)dealloc {
    [super dealloc];
    
    [myTimer invalidate];
    myTimer = nil;
}

#pragma mark -
#pragma mark view controller methods

-(IBAction)authenticateUser:(id)sender {
    // Get access to their accounts
    self.accountStore = [[[ACAccountStore alloc] init] autorelease];
    ACAccountType *accountTypeTwitter = [self.accountStore accountTypeWithAccountTypeIdentifier:ACAccountTypeIdentifierTwitter];
    [self.accountStore requestAccessToAccountsWithType:accountTypeTwitter
                                 withCompletionHandler:^(BOOL granted, NSError *error) {
                                     if (granted && !error) {
                                         //run on main thread to deal with uikit
                                         dispatch_sync(dispatch_get_main_queue(), ^{
                                             self.accounts = [self.accountStore accountsWithAccountType:accountTypeTwitter];
                                             if (self.accounts.count == 0) {
                                                 [[[[UIAlertView alloc] initWithTitle:nil message:@"Please add a Twitter account in the Settings app" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] autorelease] show];
                                             }
                                             else {
                                                 // Let them select the account they want to use
                                                 UIActionSheet* sheet = [[[UIActionSheet alloc] initWithTitle:@"Select your Twitter account:"
                                                                                                     delegate:self
                                                                                            cancelButtonTitle:nil
                                                                                       destructiveButtonTitle:nil
                                                                                            otherButtonTitles:nil] autorelease];
                                                 
                                                 for (ACAccount* accountTweet in self.accounts) {
                                                     [sheet addButtonWithTitle:accountTweet.accountDescription];
                                                 }
                                                 
                                                 sheet.tag = 0;
                                                 
                                                 [sheet showInView:self.view];
                                             }
                                         });
                                     }
                                     else {
                                         dispatch_sync(dispatch_get_main_queue(), ^{
                                             NSString* message = [NSString stringWithFormat:@"Error getting access to accounts : %@", [error localizedDescription]];
                                             [[[[UIAlertView alloc] initWithTitle:nil
                                                                          message:message
                                                                         delegate:nil
                                                                cancelButtonTitle:@"OK"
                                                                otherButtonTitles:nil] autorelease] show];
                                         });
                                     }
                                 }];
}

- (void)startTweetStream {
    //endpoint we want to call
    NSString *endpoint = @"http://api.twitter.com/1/statuses/home_timeline.json";
    //set up parameters    
    NSMutableDictionary *params = [[NSMutableDictionary alloc] init];
    [params setObject:@"1" forKey:@"include_entities"];
    [params setObject:@"50" forKey:@"count"];
    //use a since_id to limit the data sent if there is one
    if (since_id) {
        [params setObject:(NSString *)since_id forKey:@"since_id"];
    }
    //create authenticated stream
    NSLog(@"starting twewuest call");
    self.stream = [[TSStream alloc] initWithEndpoint:endpoint andParameters:params andAccount:self.account andDelegate:self];
    [self.stream start];
}

- (void)loadCoreDataTweets {
    NSLog(@"load saved core data tweets");
    
    //setup the fetch request
    NSFetchRequest *fetchRequest = [[NSFetchRequest alloc] init];
    // define the entity to use
    NSEntityDescription *entity = [NSEntityDescription entityForName:@"Tweet" inManagedObjectContext:self.managedObjectContext];
    [fetchRequest setEntity:entity];
    
    NSSortDescriptor * sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"tweetId" ascending:YES];
    NSArray * sortDescriptors = [[NSArray alloc] initWithObjects:sortDescriptor, nil];
    [fetchRequest setSortDescriptors:sortDescriptors];
    
    NSError *theError;
    NSMutableArray *results = [[self.managedObjectContext executeFetchRequest:fetchRequest error:&theError] mutableCopy];
    if (!results) {
        //serious error restart the app
        NSLog(@"encountered a serious error please restart the app!");
    }
    //display data
    [self.tweets removeAllObjects];
    for (Tweet *theTweet in results) {
        //add the tweets to tweets and update since_id
        //make user dictionary
        NSDictionary *userDict = [NSDictionary dictionaryWithObjectsAndKeys:theTweet.username,@"name", nil];
        NSDictionary *dict = [NSDictionary dictionaryWithObjectsAndKeys:userDict,@"user",theTweet.tweetId,@"id",theTweet.text,@"text", nil];
        TSTweet* model = [[[TSTweet alloc] initWithDictionary:dict] autorelease];
        since_id = [theTweet.tweetId copy];
        [self.tweets insertObject:model atIndex:0];
    }
    [tableViewTweets reloadData];
    [fetchRequest release];
}

-(IBAction)postTweet:(id)sender {
    if ([TWTweetComposeViewController canSendTweet])
    {
        TWTweetComposeViewController *tweetSheet =
        [[TWTweetComposeViewController alloc] init];
	    [self presentModalViewController:tweetSheet animated:YES];
    }
    else
    {
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Sorry" message:@"You can't send a tweet right now, make sure your device has an internet connection and you have at least one Twitter account setup" delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alertView show];
    }
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    switch (actionSheet.tag) {
        case 0: {
            if (buttonIndex < self.accounts.count) {
                self.account = [self.accounts objectAtIndex:buttonIndex];
                //set the account
                NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                [defaults setObject:[NSNumber numberWithInt:buttonIndex] forKey:@"accountIndex"];
                
                dispatch_async(backgroundQueue, ^(void) {
                    [self startTweetStream];
                });
                myTimer = [NSTimer scheduledTimerWithTimeInterval:TIMER_SECONDS target:self selector:@selector(createTweetTimer) userInfo:nil repeats:YES];
            }
        }
            break;
            default:
            break;
    }
}

#pragma mark - TSStreamDelegate

- (void)createTweetTimer {
    [self.stream release];
    dispatch_async(backgroundQueue, ^(void) {
        [self startTweetStream];
    });
}

- (void)streamDidReceiveMessage:(TSTweet *)tweet {
    // Got a new tweet! run on main thread to deal with uikit
    dispatch_async(dispatch_get_main_queue(), ^(void) {
        //update since_id
        NSLog(@"updating ui");
        since_id = [tweet.ID copy];
        [self.tweets insertObject:tweet atIndex:0];
        [self.tableViewTweets insertRowsAtIndexPaths:[NSArray arrayWithObject:[NSIndexPath indexPathForRow:0 inSection:0]]
                                    withRowAnimation:UITableViewRowAnimationNone];
    });
}

- (void)streamDidReceiveInvalidJson:(TSStream*)stream message:(NSString*)message {
    NSLog(@"--\r\nInvalid JSON!!\r\n--");
}

- (void)streamDidTimeout:(TSStream*)stream {
    NSLog(@"--\r\nStream timeout!!\r\n--");
}

- (void)streamDidFailConnection:(TSStream *)stream {
    NSLog(@"--\r\nStream failed connection!!\r\n--");
    
    // Hack to just restart it, you'll want to handle this nicer :)
    [self.stream performSelector:@selector(start) withObject:nil afterDelay:10];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.tweets.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString* const kCellIdentifier = @"Cell";
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:kCellIdentifier];
    if (!cell) {
        // Subtitle cell, with a bit of a tweak
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:kCellIdentifier] autorelease];
        cell.textLabel.font = [UIFont boldSystemFontOfSize:15];
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.font = [UIFont systemFontOfSize:15];
    }
    
    if (indexPath.row < self.tweets.count) {
        // Format the tweet
        TSTweet* tweet = [self.tweets objectAtIndex:indexPath.row];
        cell.textLabel.text = [@"@" stringByAppendingString:tweet.username];
        cell.detailTextLabel.text = tweet.text;
    }
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row < self.tweets.count) {
        // Calculate how much room we need for the tweet
        TSTweet* tweet = [self.tweets objectAtIndex:indexPath.row];
        return [tweet.text sizeWithFont:[UIFont systemFontOfSize:15]
                      constrainedToSize:CGSizeMake(tableView.bounds.size.width - 20, INT_MAX)
                          lineBreakMode:UILineBreakModeCharacterWrap].height + 40;
    }
    return 0;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
