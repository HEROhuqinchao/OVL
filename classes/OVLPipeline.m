//
//  OVLPipeline.m
//  APAASTools
//
//  Created by 胡勤超 on 2021/11/26.
//

#import "OVLPipeline.h"
#import "OVLNode.h"
#import "OVLFilter.h"
#import "OVLBlurFilter.h"
#import "OVLBlender.h"
#import "OVLMixer.h"
#import "OVLSource.h"
#import "OVLPlaneShaders.h"
#import "OVLTexture.h"
#import "OVLTexturedFilter.h"
#import "OVLLookUpFilter.h"


@implementation OVLPipeline
-(id) initWithDictionary:(NSDictionary*)json
{
    if (self = [super init]) {
        for (NSString * key in json.allKeys) {
            if ([key isEqualToString:@"filter"]) {
                self.filter = json[key];
            } else if ([key isEqualToString:@"type"]) {
                self.type = json[key];
            } else if ([key isEqualToString:@"vertex"]) {
                self.vertex = json[key];
            } else if ([key isEqualToString:@"hidden"]) {
                self.hidden = json[key];
            } else if ([key isEqualToString:@"blur"]) {
                self.blur = json[key];
            } else if ([key isEqualToString:@"audio"]) {
                self.audio = json[key];
            } else if ([key isEqualToString:@"orientation"]) {
                self.orientation = json[key];
            } else if ([key isEqualToString:@"lookup"]) {
                self.lookup = json[key];
            } else { //attr
                self.attr = json[key];
            }
        }
    }
    return self;
}

@end
