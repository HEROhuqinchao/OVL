//
//  OVLNode.m
//  cartoon
//
//  Created by satoshi on 10/27/13.
//  Copyright (c) 2013 satoshi. All rights reserved.
//

#import "OVLNode.h"
#import "OVLSwap.h"
#import "OVLFork.h"
#import "OVLShift.h"
#import "OVLPrev.h"

@implementation OVLNode
@dynamic shader;

+(id) swap {
    return [[OVLSwap alloc] init];
}

+(id) shift {
    return [[OVLShift alloc] init];
}

+(id) fork {
    return [[OVLFork alloc] init];
}

+(id) push {
    return [[OVLPrev alloc] init];
}

-(void) process:(id <OVLNodeDelegate>)delegate {
    // To be implemented by subclasses
}

-(NSString*) nodeKey {
    return @"N/A";
}

-(BOOL) emulate:(NSMutableArray*)stack {
    return NO;
}

-(NSString*) stringFromAttrs {
    return @"";
}

-(void) setPixelSize:(const GLfloat*)pv delegate:(id <OVLNodeDelegate>)delegate {
    [self set2fv:pv forName:"uPixel"];
}

-(void) set2fv:(const GLfloat*)pv forName:(const GLchar*)name {
    // No operation
}

-(void) compile {
}

-(void) clearProgram {
}

-(NSString*) shader {
    return nil;
}

-(id) attrForName:(NSString*)name {
    return nil;
}

-(void) setAttr:(id)value forName:(NSString*)name {
}

-(void) setDefault {
}

-(NSDictionary*) jsonObject {
    return nil;
}

-(NSSet*) hiddenKeys {
    return nil;
}

-(NSDictionary*) attributes {
    return nil;
}

-(void) setAttributes:(NSDictionary*)attributes {
}

-(BOOL) hasPrimary {
    return NO; 
}

-(BOOL) isPrimeryKey:(NSString*)key {
    return NO;
}

-(void) addPrimaryKey:(NSString*)key {
}

-(void) removePrimaryKey:(NSString*)key {
}

-(void) removeAllPrimaryKeys {
}

-(void) setOrientation:(UIDeviceOrientation)orientation {
}



-(NSArray*) primaryAttributeKeys {
    return nil;
}
@end
