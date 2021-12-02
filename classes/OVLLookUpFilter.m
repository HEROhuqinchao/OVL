//
//  OVLBlender.m
//  cartoon
//
//  Created by satoshi on 10/27/13.
//  Copyright (c) 2013 satoshi. All rights reserved.
//

#import "OVLLookUpFilter.h"
#import "OVLPlaneShaders.h"

@interface OVLLookUpFilter() {
    GLKTextureInfo* _texture;
    GLuint  _textureID;
}
@end
@implementation OVLLookUpFilter

-(void) compile {
    [super compile];
    _uTexture2 = glGetUniformLocation(_ph, "uTexture2");
}
-(void) innerProcess:(UIDeviceOrientation)orientation {
    
    
    glActiveTexture(GL_TEXTURE0 + TEXTURE_INDEX_TEXTURE);
    glBindTexture(GL_TEXTURE_2D, _texture.name);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    // clipping will be done by the vertex shader
    //glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    //glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glUniform1i(_uTexture2, TEXTURE_INDEX_TEXTURE);
}

-(void) deferredSetAttr:(id)value forName:(NSString *)name {
    if ([name isEqualToString:@"texture"]) {
        if ([value isKindOfClass:[NSString class]]) {
            glUseProgram(_ph);
            GLenum glError = glGetError(); // HACK to work around OpenGL bug (see the link above)
            if (glError) {
                NSLog(@"OVLTF glError = %d", glError);
            }
            _textureID =  [self  createTextureWithImage:value];
        }
    } else {
        [super deferredSetAttr:value forName:name];
    }
}

// 从图片中加载纹理
- (GLuint)createTextureWithImage:(NSString *)fileName {
    //加载纹理
    CGImageRef image = [UIImage imageNamed:fileName].CGImage;
    if(!image){
        NSLog(@"texture image load fail");
        exit(1);
    }
    //图片宽高
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    GLubyte *data = (GLubyte *)calloc(width * height * 4, sizeof(GLubyte));
    /**
     参数1: 渲染绘制地址
     参数2:宽度
     参数3:高度
     参数4:RGB颜色空间，每个颜色通道一般是8位
     参数5:颜色空间
     参数6:颜色通道：RGBA=kCGImageAlphaPremultipliedLast
     */
    CGContextRef context = CGBitmapContextCreate(data, width, height, 8, width * 4, CGImageGetColorSpace(image), kCGImageAlphaPremultipliedLast);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);
    GLuint  textureID = 0;
    glBindTexture(GL_TEXTURE_2D, textureID);
    //设置纹理参数使用缩小滤波器和线性滤波器（加权平均）--设置纹理属性
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    //设置纹理参数使用放大滤波器和线性滤波器（加权平均）--设置纹理属性
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    float fw = width,fh = height;
    /**
     生成2D纹理
     参数1:target,纹理目标，因为你使用的是glTexImage2D函数，所以必须设置为GL_TEXTURE_2D
     参数2:level，0，基本图像级
     参数3:颜色组件，GL_RGBA，GL_ALPHA，GL_RGBA
     参数4:宽度
     参数5:高度
     参数6:纹理边框宽度
     参数7:像素颜色格式
     参数8:像素数据类型
     参数9:数据地址
     */
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, fw, fh, 0, GL_RGBA, GL_UNSIGNED_BYTE, data);
    glBindTexture(GL_TEXTURE_2D, textureID);
    free(data);
    
    return textureID;
}


@end
