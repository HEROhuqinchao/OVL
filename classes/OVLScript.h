//
//  OVLScript.h
//  cartoon
//
//  Created by satoshi on 11/7/13.
//  Copyright (c) 2013 satoshi. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

@class OVLNode;
@interface OVLScript : NSObject
@property (nonatomic, retain) NSMutableArray* nodes;
-(id) initWithDictionary:(NSDictionary*)json;
-(void) compile;
-(OVLNode*) primaryNode;
-(void) setOrientation:(UIDeviceOrientation)orientation;
@end
