//
//  OVLPipeline.h
//  APAASTools
//
//  Created by 胡勤超 on 2021/11/26.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN

@interface OVLPipeline : NSObject
@property (nonatomic, strong) NSString *filter;
@property (nonatomic, strong) NSString *type;
@property (nonatomic, strong) NSString *vertex;
@property (nonatomic) BOOL hidden;
@property (nonatomic) BOOL blur;
@property (nonatomic) BOOL audio;
@property (nonatomic) BOOL orientation;
@property (nonatomic) BOOL texture;
@property (nonatomic) BOOL lookup;
@property (nonatomic, strong) NSDictionary *attr;

-(id) initWithDictionary:(NSDictionary*)json;
@end

NS_ASSUME_NONNULL_END
