//
//  Tweet.h
//  OBSTwitter
//
//  Created by Adam Bemowski on 11/4/12.
//  Copyright (c) 2012 OBS. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>


@interface Tweet : NSManagedObject

@property (nonatomic, retain) NSString * username;
@property (nonatomic, retain) NSString * text;
@property (nonatomic, retain) NSString * tweetId;

@end
