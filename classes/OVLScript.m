//
//  OVLScript.m
//  cartoon
//
//  Created by satoshi on 11/7/13.
//  Copyright (c) 2013 satoshi. All rights reserved.
//

#import "OVLScript.h"
#import "OVLNode.h"
#import "OVLFilter.h"
#import "OVLPipeline.h"
#import "OVLBlurFilter.h"
#import "OVLBlender.h"
#import "OVLMixer.h"
#import "OVLSource.h"
#import "OVLPlaneShaders.h"
#import "OVLTexture.h"
#import "OVLTexturedFilter.h"
#import "OVLLookUpFilter.h"

@interface OVLScript() {
    NSMutableDictionary* _script;
}
@end

@implementation OVLScript

-(id) initWithDictionary:(NSDictionary*)json {
    if (self = [super init]) {
        _script = [NSMutableDictionary dictionaryWithDictionary:json];
        self.nodes = [OVLScript parseScript:_script[@"pipeline"]];
    }
    return self;
}

-(void) compile {
    for (OVLNode* node in self.nodes) {
        [node compile];
    }
}

// Returns the first primerty node
-(OVLNode*) primaryNode {
    for (OVLNode* node in self.nodes) {
        if (node.hasPrimary) {
            return node;
        }
    }
    return nil;
}

+(NSMutableArray*) parseScript:(NSArray*)nodes {
    NSMutableArray* nodeList = [NSMutableArray array];
    for (NSDictionary* node in nodes) {
        NSString* control = node[@"control"];
        NSString* filter = node[@"filter"];
        NSString* blender = node[@"blender"];
        NSString* mixer = node[@"mixer"];
        NSString* source = node[@"source"];
        OVLPipeline *pipeline = [[OVLPipeline alloc] initWithDictionary:node];
        if (filter || blender || mixer || source) {
            OVLFilter* filterNode;
            if (filter) {
                if (pipeline.blur) {
                    filterNode = [OVLBlurFilter alloc];
                } else if (pipeline.texture) {
                    filterNode = [OVLTexturedFilter alloc];
                } else if (pipeline.lookup) {
                    filterNode = [OVLLookUpFilter alloc];
                } else {
                    filterNode = [OVLFilter alloc];
                }
            } else if (blender) {
                filterNode = [OVLBlender alloc];
                filter = blender;
            } else if (mixer) {
                filterNode = [OVLMixer alloc];
                filter = mixer;
            } else {
                if (pipeline.texture) {
                    filterNode = [OVLTexture alloc];
                } else {
                    filterNode = [OVLSource alloc];
                }
                filter = source;
            }
            if (pipeline.orientation) {
                filterNode.fOrientation = YES;
            }
            if (pipeline.audio) {
                filterNode.fAudio = YES;
            }
            NSString* vertex = node[@"vertex"];
            vertex = vertex ? vertex : @"simple";
            if (![filter isKindOfClass:[NSString class]] || !vertex) {
                NSLog(@"OVLSc invalid filter(%@) or vertex(%@", filter, vertex);
                continue;
            }
            filterNode = [filterNode initWithVertexShader:vertex fragmentShader:filter];
            filterNode.repeat = ((NSNumber*)node[@"repeat"]).intValue;
            filterNode.fork = (((NSNumber*)node[@"fork"]).boolValue);
            [filterNode setUI:node[@"ui"]];
            [filterNode setExtra:node[@"extra"]];
            NSDictionary* attrs = node[@"attr"];
            if (attrs && ![attrs isKindOfClass:[NSDictionary class]]) {
                NSLog(@"OVLSc invalid attrs type (%@)", [attrs class]);
                continue;
            }
            for (NSString* key in attrs.allKeys) {
                id attr = attrs[key];
                [filterNode setAttr:attr forName:key];
            }
            [nodeList addObject:filterNode];
        } else if ([control isEqualToString:@"fork"]) {
            [nodeList addObject:[OVLNode fork]];
        } else if ([control isEqualToString:@"swap"]) {
            [nodeList addObject:[OVLNode swap]];
        } else if ([control isEqualToString:@"shift"]) {
            [nodeList addObject:[OVLNode shift]];
        } else if ([control isEqualToString:@"previous"]) {
            [nodeList addObject:[OVLNode push]];
        }
    }
    return nodeList;
}

-(void) setOrientation:(UIDeviceOrientation)orientation {
    for (OVLNode* node in _nodes) {
        [node setOrientation:orientation];
    }
}

@end
