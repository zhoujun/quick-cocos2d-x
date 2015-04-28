/****************************************************************************
Copyright (c) 2010 cocos2d-x.org

http://www.cocos2d-x.org

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
****************************************************************************/
#include <Foundation/Foundation.h>
#include <Cocoa/Cocoa.h>
#include "CCDirector.h"
#include "ccMacros.h"
#include "CCImage.h"
#include "CCFileUtils.h"
#include "CCTexture2D.h"
#include <string>
#include <sys/stat.h>
#include <stdio.h>
#include <unistd.h>
#include "apptools/HelperFunc.h"

typedef struct
{
    unsigned int height;
    unsigned int width;
    int          bitsPerComponent;
    bool         hasAlpha;
    bool         isPremultipliedAlpha;
    bool         hasShadow;
    CGSize       shadowOffset;
    float        shadowBlur;
    float        shadowOpacity;
    bool         hasStroke;
    float        strokeColorR;
    float        strokeColorG;
    float        strokeColorB;
    float        strokeSize;
    float        tintColorR;
    float        tintColorG;
    float        tintColorB;
    unsigned char*  data;
} tImageInfo;

static unsigned int nextPOT(unsigned int x)
{
    x = x - 1;
    x = x | (x >> 1);
    x = x | (x >> 2);
    x = x | (x >> 4);
    x = x | (x >> 8);
    x = x | (x >> 16);
    return x + 1;
}

typedef enum {
    kCCTexture2DPixelFormat_Automatic = 0,
        //! 32-bit texture: RGBA8888
    kCCTexture2DPixelFormat_RGBA8888,
        //! 24-bit texture: RGBA888
    kCCTexture2DPixelFormat_RGB888,
        //! 16-bit texture without Alpha channel
    kCCTexture2DPixelFormat_RGB565,
        //! 8-bit textures used as masks
    kCCTexture2DPixelFormat_A8,
        //! 16-bit textures: RGBA4444
    kCCTexture2DPixelFormat_RGBA4444,
        //! 16-bit textures: RGB5A1
    kCCTexture2DPixelFormat_RGB5A1,    
    
        //! Default texture format: RGBA8888
    kCCTexture2DPixelFormat_Default = kCCTexture2DPixelFormat_RGBA8888,
    
        // backward compatibility stuff
    kTexture2DPixelFormat_Automatic = kCCTexture2DPixelFormat_Automatic,
    kTexture2DPixelFormat_RGBA8888 = kCCTexture2DPixelFormat_RGBA8888,
    kTexture2DPixelFormat_RGB888 = kCCTexture2DPixelFormat_RGB888,
    kTexture2DPixelFormat_RGB565 = kCCTexture2DPixelFormat_RGB565,
    kTexture2DPixelFormat_A8 = kCCTexture2DPixelFormat_A8,
    kTexture2DPixelFormat_RGBA4444 = kCCTexture2DPixelFormat_RGBA4444,
    kTexture2DPixelFormat_RGB5A1 = kCCTexture2DPixelFormat_RGB5A1,
    kTexture2DPixelFormat_Default = kCCTexture2DPixelFormat_Default
    
} CCTexture2DPixelFormat;

static bool _initPremultipliedATextureWithImage(CGImageRef image, NSUInteger POTWide, NSUInteger POTHigh, tImageInfo *pImageInfo)
{
    NSUInteger            i;
    CGContextRef        context = nil;
    unsigned char*        data = nil;;
    CGColorSpaceRef        colorSpace;
    unsigned char*        tempData;
    unsigned int*        inPixel32;
    unsigned short*        outPixel16;
    bool                hasAlpha;
    CGImageAlphaInfo    info;
    CGSize                imageSize;
    CCTexture2DPixelFormat    pixelFormat;
    
    info = CGImageGetAlphaInfo(image);
    hasAlpha = ((info == kCGImageAlphaPremultipliedLast) || (info == kCGImageAlphaPremultipliedFirst) || (info == kCGImageAlphaLast) || (info == kCGImageAlphaFirst) ? YES : NO);
    
    size_t bpp = CGImageGetBitsPerComponent(image);
    colorSpace = CGImageGetColorSpace(image);
    
    if(colorSpace) 
    {
        if(hasAlpha || bpp >= 8)
        {
            pixelFormat = kCCTexture2DPixelFormat_Default;
        }
        else 
        {
            pixelFormat = kCCTexture2DPixelFormat_RGB565;
        }
    } 
    else  
    {
        // NOTE: No colorspace means a mask image
        pixelFormat = kCCTexture2DPixelFormat_A8;
    }
    
    imageSize.width = CGImageGetWidth(image);
    imageSize.height = CGImageGetHeight(image);
    
    // Create the bitmap graphics context
    
    switch(pixelFormat) 
    {      
        case kCCTexture2DPixelFormat_RGBA8888:
        case kCCTexture2DPixelFormat_RGBA4444:
        case kCCTexture2DPixelFormat_RGB5A1:
            colorSpace = CGColorSpaceCreateDeviceRGB();
            data = new unsigned char[POTHigh * POTWide * 4];
            info = hasAlpha ? kCGImageAlphaPremultipliedLast : kCGImageAlphaNoneSkipLast;
            context = CGBitmapContextCreate(data, POTWide, POTHigh, 8, 4 * POTWide, colorSpace, info | kCGBitmapByteOrder32Big);                
            CGColorSpaceRelease(colorSpace);
            break;
            
        case kCCTexture2DPixelFormat_RGB565:
            colorSpace = CGColorSpaceCreateDeviceRGB();
            data = new unsigned char[POTHigh * POTWide * 4];
            info = kCGImageAlphaNoneSkipLast;
            context = CGBitmapContextCreate(data, POTWide, POTHigh, 8, 4 * POTWide, colorSpace, info | kCGBitmapByteOrder32Big);
            CGColorSpaceRelease(colorSpace);
            break;
        case kCCTexture2DPixelFormat_A8:
            data = new unsigned char[POTHigh * POTWide];
            info = kCGImageAlphaOnly;
            context = CGBitmapContextCreate(data, POTWide, POTHigh, 8, POTWide, NULL, info);
            break;            
        default:
            return false;
    }
    
    CGRect rect;
    rect.size.width = POTWide;
    rect.size.height = POTHigh;
    rect.origin.x = 0;
    rect.origin.y = 0;
    
    CGContextClearRect(context, rect);
    CGContextTranslateCTM(context, 0, 0);
    CGContextDrawImage(context, rect, image);
    
    // Repack the pixel data into the right format
    
    if(pixelFormat == kCCTexture2DPixelFormat_RGB565) 
    {
        //Convert "RRRRRRRRRGGGGGGGGBBBBBBBBAAAAAAAA" to "RRRRRGGGGGGBBBBB"
        tempData = new unsigned char[POTHigh * POTWide * 2];
        inPixel32 = (unsigned int*)data;
        outPixel16 = (unsigned short*)tempData;
        for(i = 0; i < POTWide * POTHigh; ++i, ++inPixel32)
        {
            *outPixel16++ = ((((*inPixel32 >> 0) & 0xFF) >> 3) << 11) | ((((*inPixel32 >> 8) & 0xFF) >> 2) << 5) | ((((*inPixel32 >> 16) & 0xFF) >> 3) << 0);
        }

        delete []data;
        data = tempData;
        
    }
    else if (pixelFormat == kCCTexture2DPixelFormat_RGBA4444) 
    {
        //Convert "RRRRRRRRRGGGGGGGGBBBBBBBBAAAAAAAA" to "RRRRGGGGBBBBAAAA"
        tempData = new unsigned char[POTHigh * POTWide * 2];
        inPixel32 = (unsigned int*)data;
        outPixel16 = (unsigned short*)tempData;
        for(i = 0; i < POTWide * POTHigh; ++i, ++inPixel32)
        {
            *outPixel16++ = 
            ((((*inPixel32 >> 0) & 0xFF) >> 4) << 12) | // R
            ((((*inPixel32 >> 8) & 0xFF) >> 4) << 8) | // G
            ((((*inPixel32 >> 16) & 0xFF) >> 4) << 4) | // B
            ((((*inPixel32 >> 24) & 0xFF) >> 4) << 0); // A
        }       
        
        delete []data;
        data = tempData;
        
    }
    else if (pixelFormat == kCCTexture2DPixelFormat_RGB5A1) 
    {
        //Convert "RRRRRRRRRGGGGGGGGBBBBBBBBAAAAAAAA" to "RRRRRGGGGGBBBBBA"
        tempData = new unsigned char[POTHigh * POTWide * 2];
        inPixel32 = (unsigned int*)data;
        outPixel16 = (unsigned short*)tempData;
        for(i = 0; i < POTWide * POTHigh; ++i, ++inPixel32)
        {
            *outPixel16++ = 
            ((((*inPixel32 >> 0) & 0xFF) >> 3) << 11) | // R
            ((((*inPixel32 >> 8) & 0xFF) >> 3) << 6) | // G
            ((((*inPixel32 >> 16) & 0xFF) >> 3) << 1) | // B
            ((((*inPixel32 >> 24) & 0xFF) >> 7) << 0); // A
        }
                
        delete []data;
        data = tempData;
    }
    
    // should be after calling super init
    pImageInfo->isPremultipliedAlpha = true;
    pImageInfo->hasAlpha = true;
    pImageInfo->bitsPerComponent = (int)bpp;
    pImageInfo->width = (unsigned int)POTWide;
    pImageInfo->height = (unsigned int)POTHigh;
    
    if (pImageInfo->data)
    {
        delete [] pImageInfo->data;
    }
    pImageInfo->data = data;
    
    CGContextRelease(context);
    return true;
}
// TODO: rename _initWithImage, it also makes a draw call.
static bool _initWithImage(CGImageRef CGImage, tImageInfo *pImageinfo, double scaleX, double scaleY)
{
    NSUInteger POTWide, POTHigh;
    
    if(CGImage == NULL) 
    {
        return false;
    }
    
	//if (cocos2d::CCImage::getIsScaleEnabled())
	if( cocos2d::CCDirector::sharedDirector()->getContentScaleFactor() > 1.0f )
	{
		POTWide = CGImageGetWidth(CGImage) * scaleX;
		POTHigh = CGImageGetHeight(CGImage) * scaleY;
	}
	else 
	{
		POTWide = CGImageGetWidth(CGImage);
		POTHigh = CGImageGetHeight(CGImage);
	}

    
    // load and draw image
    return _initPremultipliedATextureWithImage(CGImage, POTWide, POTHigh, pImageinfo);
}

static bool _initWithFile(const char* path, tImageInfo *pImageinfo)
{
    CGImageRef                CGImage;    
    NSImage                    *jpg;
    //NSImage                    *png;
    bool            ret;
    
    // convert jpg to png before loading the texture
    
    //NSString *fullPath = [NSString stringWithUTF8String:path];
	unsigned long fileSize = 0;
	unsigned char* pFileData = cocos2d::CZHelperFunc::getFileData(path, "rb", &fileSize);
    NSData *adata = [[NSData alloc] initWithBytes:pFileData length:fileSize];
	delete []pFileData;
    jpg = [[NSImage alloc] initWithData:adata];
    //jpg = [[NSImage alloc] initWithContentsOfFile: fullPath];
    //png = [[NSImage alloc] initWithData:UIImagePNGRepresentation(jpg)];
    CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)[jpg TIFFRepresentation], NULL);
    CGImage = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    
    ret = _initWithImage(CGImage, pImageinfo, 1.0, 1.0);
    
    //[png release];
    [jpg release];
    if (CGImage) CFRelease(CGImage);
    if (source) CFRelease(source);
  
    return ret;
}

// TODO: rename _initWithData, it also makes a draw call.
static bool _initWithData(void * pBuffer, int length, tImageInfo *pImageinfo, double scaleX, double scaleY)
{
    bool ret = false;
    
    if (pBuffer) 
    {
        CGImageRef CGImage;
        NSData *data;
        
        data = [NSData dataWithBytes:pBuffer length:length];
		CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)data, NULL);
        CGImage = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        
        ret = _initWithImage(CGImage, pImageinfo, scaleX, scaleY);
        if (CGImage) CFRelease(CGImage);
        if (source) CFRelease(source);
    }
    return ret;
}

static bool _isValidFontName(const char *fontName)
{
    bool ret = false;
#if 0 
    NSString *fontNameNS = [NSString stringWithUTF8String:fontName];
    
    for (NSString *familiName in [NSFont familyNames]) 
    {
        if ([familiName isEqualToString:fontNameNS]) 
        {
            ret = true;
            goto out;
        }
        
        for(NSString *font in [NSFont fontNamesForFamilyName: familiName])
        {
            if ([font isEqualToString: fontNameNS])
            {
                ret = true;
                goto out;
            }
        }
    }
#endif
    out:
    return ret;
}

static bool _initWithString(const char * pText, cocos2d::CCImage::ETextAlign eAlign, const char * pFontName, int nSize, tImageInfo* pInfo)
{
    bool bRet = false;

	CCAssert(pText, "Invalid pText");
	CCAssert(pInfo, "Invalid pInfo");
	
	do {
		NSString * string  = [NSString stringWithUTF8String:pText];
        NSString * fntName = [NSString stringWithUTF8String:pFontName];
        fntName = [[fntName lastPathComponent] stringByDeletingPathExtension];
		// font
        NSFont *font = [NSFont fontWithName:fntName size:nSize];
		
		if (font == nil) {
			font = [[NSFontManager sharedFontManager]
					fontWithFamily:@"Arial"
					traits:NSUnboldFontMask | NSUnitalicFontMask
					weight:0
					size:nSize];
		}
		CC_BREAK_IF(!font);
		
		// color
        NSColor* foregroundColor = [NSColor colorWithDeviceRed:pInfo->tintColorR green:pInfo->tintColorG blue:pInfo->tintColorB alpha:1];

        //stroke Color
        NSColor * strokeColor;
        if (pInfo->hasStroke) {
            strokeColor = [NSColor colorWithDeviceRed:pInfo->strokeColorR
                                                green:pInfo->strokeColorG
                                                 blue:pInfo->strokeColorB
                                                alpha:1];
        } else {
            strokeColor = [NSColor whiteColor];
        }
        
		// alignment, linebreak
		unsigned uHoriFlag = eAlign & 0x0f;
		unsigned uVertFlag = (eAlign >> 4) & 0x0f;
		NSTextAlignment align = (2 == uHoriFlag) ? NSRightTextAlignment
			: (3 == uHoriFlag) ? NSCenterTextAlignment
			: NSLeftTextAlignment;
		
		NSMutableParagraphStyle *paragraphStyle = [[[NSMutableParagraphStyle alloc] init] autorelease];
		[paragraphStyle setParagraphStyle:[NSParagraphStyle defaultParagraphStyle]];
		[paragraphStyle setLineBreakMode:NSLineBreakByCharWrapping];
		[paragraphStyle setAlignment:align];

		// attribute
        NSDictionary *tokenAttributesDict;
        if (pInfo->hasStroke) {
            
            tokenAttributesDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                   foregroundColor,NSForegroundColorAttributeName,
                                   [NSNumber numberWithFloat: - pInfo->strokeSize],NSStrokeWidthAttributeName,
                                   strokeColor,NSStrokeColorAttributeName,
                                   font, NSFontAttributeName,
                                   paragraphStyle, NSParagraphStyleAttributeName, nil];
        }else {
            tokenAttributesDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                   foregroundColor,NSForegroundColorAttributeName,
                                   font, NSFontAttributeName,
                                   paragraphStyle, NSParagraphStyleAttributeName, nil];
        }

		// linebreak
		if (pInfo->width > 0) {
			if ([string sizeWithAttributes:tokenAttributesDict].width > pInfo->width) {
				NSMutableString *lineBreak = [[[NSMutableString alloc] init] autorelease];
				NSUInteger length = [string length];
				NSRange range = NSMakeRange(0, 1);
				NSUInteger width = 0;
				NSUInteger lastBreakLocation = 0;
				for (NSUInteger i = 0; i < length; i++) {
					range.location = i;
					NSString *character = [string substringWithRange:range];
					[lineBreak appendString:character];
					if ([@"!?.,-= " rangeOfString:character].location != NSNotFound) { lastBreakLocation = i; }
					width = [lineBreak sizeWithAttributes:tokenAttributesDict].width;
					if (width > pInfo->width) {
						[lineBreak insertString:@"\r\n" atIndex:(lastBreakLocation > 0) ? lastBreakLocation : [lineBreak length] - 1];
					}
				}
				string = lineBreak;
			}
		}

		NSAttributedString *stringWithAttributes =[[[NSAttributedString alloc] initWithString:string
										 attributes:tokenAttributesDict] autorelease];
				
		NSSize realDimensions = [stringWithAttributes size];
		// Mac crashes if the width or height is 0
		CC_BREAK_IF(realDimensions.width <= 0 || realDimensions.height <= 0);
				
		CGSize dimensions = CGSizeMake(pInfo->width, pInfo->height);
		
	
		if(dimensions.width <= 0 && dimensions.height <= 0) {
			dimensions.width = realDimensions.width;
			dimensions.height = realDimensions.height;
		} else if (dimensions.height <= 0) {
			dimensions.height = realDimensions.height;
		}

        dimensions.width = (int)(dimensions.width / 2) * 2 + 2;
        dimensions.height = (int)(dimensions.height / 2) * 2 + 2;

		NSUInteger POTWide = (NSUInteger)dimensions.width;
		NSUInteger POTHigh = (NSUInteger)(MAX(dimensions.height, realDimensions.height));
		unsigned char*			data;
		//Alignment
			
		CGFloat xPadding = 0;
		switch (align) {
			case NSLeftTextAlignment: xPadding = 0; break;
			case NSCenterTextAlignment: xPadding = (dimensions.width-realDimensions.width)/2.0f; break;
			case NSRightTextAlignment: xPadding = dimensions.width-realDimensions.width; break;
			default: break;
		}

		// 1: TOP
		// 2: BOTTOM
		// 3: CENTER
		CGFloat yPadding = (1 == uVertFlag || realDimensions.height >= dimensions.height) ? (dimensions.height - realDimensions.height)	// align to top
		: (2 == uVertFlag) ? 0																	// align to bottom
		: (dimensions.height - realDimensions.height) / 2.0f;									// align to center
		
		
		NSRect textRect = NSMakeRect(xPadding, POTHigh - dimensions.height + yPadding, realDimensions.width, realDimensions.height);
		//Disable antialias
		
		[[NSGraphicsContext currentContext] setShouldAntialias:NO];	
		
		NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(POTWide, POTHigh)];
        
		[image lockFocus];
        
        // patch for mac retina display and lableTTF
        [[NSAffineTransform transform] set];
		
		//[stringWithAttributes drawAtPoint:NSMakePoint(xPadding, offsetY)]; // draw at offset position	
		[stringWithAttributes drawInRect:textRect];
		//[stringWithAttributes drawInRect:textRect withAttributes:tokenAttributesDict];
		NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithFocusedViewRect:NSMakeRect (0.0f, 0.0f, POTWide, POTHigh)];
		[image unlockFocus];
		
		data = (unsigned char*) [bitmap bitmapData];  //Use the same buffer to improve the performance.
		
		NSUInteger textureSize = POTWide*POTHigh*4;
		
		unsigned char* dataNew = new unsigned char[textureSize];
		if (dataNew) {
			memcpy(dataNew, data, textureSize);
			// output params
			pInfo->width = (unsigned int)POTWide;
			pInfo->height = (unsigned int)POTHigh;
			pInfo->data = dataNew;
			pInfo->hasAlpha = true;
			pInfo->isPremultipliedAlpha = true;
			pInfo->bitsPerComponent = 8;
			bRet = true;
		}
		[bitmap release];
		[image release];
	} while (0);
    return bRet;
}

NS_CC_BEGIN

static bool m_bEnabledScale = true;

bool isFileExists(const char* szFilePath);

bool isFileExists(const char* szFilePath)
{
#if CC_TARGET_PLATFORM == CC_PLATFORM_WIN32
	//TCHAR dirpath[MAX_PATH];
	//MultiByteToWideChar(936,0,szFilePath,-1,dirpath,sizeof(dirpath));
	DWORD dwFileAttr = GetFileAttributesA(szFilePath);
	if (INVALID_FILE_ATTRIBUTES == dwFileAttr
		|| (dwFileAttr&FILE_ATTRIBUTE_DIRECTORY))	{
		return false;
	}		
#elif CC_TARGET_PLATFORM == CC_PLATFORM_ANDROID
	bool bFind = true;
	do 
	{
		struct stat buf;
		int n = stat(szFilePath, &buf);
		if ((0 != n)
			|| !(buf.st_mode&S_IFMT))	
		{
			bFind = false;
		}
	} while (0);
	if (!bFind)
	{
		//std::string strFilenName = s_strRelativePath + szFilePath;
		unsigned char * pBuffer = NULL;
		unzFile pFile = NULL;
		unsigned long pSize = 0;
		
		do 
		{
			pFile = unzOpen(s_strAndroidPackagePath.c_str());
			if(!pFile)break;
			
			int nRet = unzLocateFile(pFile, szFilePath, 1);
			if(UNZ_OK != nRet)
				bFind = false;
			else
				bFind = true;
		} while (0);
		
		if (pFile)
		{
			unzClose(pFile);
		}
	}
	
	return bFind;
#else
	struct stat buf;
	int n = stat(szFilePath, &buf);
	if ((0 != n)
		|| !(buf.st_mode&S_IFMT))	{
		return false;
	}		
	
#endif
	return true;
}

CCImage::CCImage()
: m_nWidth(0)
, m_nHeight(0)
, m_nBitsPerComponent(0)
, m_pData(0)
, m_bHasAlpha(false)
, m_bPreMulti(false)
{
    
}

CCImage::~CCImage()
{
    CC_SAFE_DELETE_ARRAY(m_pData);
}

bool CCImage::initWithImageFile(const char * strPath, EImageFormat eImgFmt/* = eFmtPng*/)
{
    std::string strTemp = CCFileUtils::sharedFileUtils()->fullPathForFilename(strPath);
	if (m_bEnabledScale)
	{
		if (!isFileExists(strTemp.c_str()))
		{
			if (strTemp.rfind("@2x") == std::string::npos)
			{
				size_t t = strTemp.rfind(".");
				if (t != std::string::npos)
				{
					strTemp.insert(t, "@2x");
				}
/*				CCSize size = CCDirector::sharedDirector()->getWinSize();		
	#if (CC_TARGET_PLATFORM == CC_PLATFORM_ANDROID)
				m_dScaleX = size.width/800.0f;
				m_dScaleY = size.height/480.0f;
	#else
				m_dScaleX = size.width/960.0f;
				m_dScaleY = size.height/640.0f;
				
	#endif
*/
			}
		}    
		else
		{
//			m_dScaleX = 1.0;
//			m_dScaleY = 1.0;
		}
	}
	
//	CCFileData tempData(strTemp.c_str(), "rb");			
//	return initWithImageData(tempData.getBuffer(), tempData.getSize(), eImgFmt);

	unsigned long fileSize = 0;
	//unsigned char* pFileData = CCFileUtils::sharedFileUtils()->getFileData(strTemp.c_str(), "rb", &fileSize);
	unsigned char* pFileData = CZHelperFunc::getFileData(strTemp.c_str(), "rb", &fileSize);
	bool ret = initWithImageData(pFileData, (int)fileSize, eImgFmt);
	delete []pFileData;
	return ret;
}

bool CCImage::initWithImageFileThreadSafe(const char *fullpath, EImageFormat imageType)
{
    /*
     * CCFileUtils::fullPathFromRelativePath() is not thread-safe, it use autorelease().
     */
    bool bRet = false;
    unsigned long nSize = 0;
    //unsigned char* pBuffer = CCFileUtils::sharedFileUtils()->getFileData(fullpath, "rb", &nSize);
    unsigned char* pBuffer = CZHelperFunc::getFileData(fullpath, "rb", &nSize);
    if (pBuffer != NULL && nSize > 0)
    {
        bRet = initWithImageData(pBuffer, (int)nSize, imageType);
    }
    CC_SAFE_DELETE_ARRAY(pBuffer);
    return bRet;
}



/*
// please uncomment this and integrate it somehow if you know what your doing, thanks
bool CCImage::potImageData(unsigned int POTWide, unsigned int POTHigh)
{
	unsigned char*			data = NULL;
	unsigned char*			tempData =NULL;
	unsigned int*				inPixel32 = NULL;
	unsigned short*			outPixel16 = NULL;
	bool					hasAlpha;
	CCTexture2DPixelFormat	pixelFormat;
	
	hasAlpha = this->hasAlpha();
	
	size_t bpp = this->getBitsPerComponent();
	
    // compute pixel format
	if(hasAlpha)
	{
		pixelFormat = CCTexture2D::defaultAlphaPixelFormat();
	}
	else
	{
		if (bpp >= 8)
		{
			pixelFormat = kCCTexture2DPixelFormat_RGB888;
		}
		else
		{
			CCLOG("cocos2d: CCTexture2D: Using RGB565 texture since image has no alpha");
			pixelFormat = kCCTexture2DPixelFormat_RGB565;
		}
	}
	
	switch(pixelFormat) {          
		case kCCTexture2DPixelFormat_RGBA8888:
		case kCCTexture2DPixelFormat_RGBA4444:
		case kCCTexture2DPixelFormat_RGB5A1:
		case kCCTexture2DPixelFormat_RGB565:
		case kCCTexture2DPixelFormat_A8:
			tempData = (unsigned char*)(this->getData());
			CCAssert(tempData != NULL, "NULL image data.");
			
			if(this->getWidth() == (short)POTWide && this->getHeight() == (short)POTHigh)
			{
				data = new unsigned char[POTHigh * POTWide * 4];
				memcpy(data, tempData, POTHigh * POTWide * 4);
			}
			else
			{
				data = new unsigned char[POTHigh * POTWide * 4];
				memset(data, 0, POTHigh * POTWide * 4);
				
				unsigned char* pPixelData = (unsigned char*) tempData;
				unsigned char* pTargetData = (unsigned char*) data;
				
				int imageHeight = this->getHeight();
				for(int y = 0; y < imageHeight; ++y)
				{
					memcpy(pTargetData+POTWide*4*y, pPixelData+(this->getWidth())*4*y, (this->getWidth())*4);
				}
			}
			
			break;    
		case kCCTexture2DPixelFormat_RGB888:
			tempData = (unsigned char*)(this->getData());
			CCAssert(tempData != NULL, "NULL image data.");
			if(this->getWidth() == (short)POTWide && this->getHeight() == (short)POTHigh)
			{
				data = new unsigned char[POTHigh * POTWide * 3];
				memcpy(data, tempData, POTHigh * POTWide * 3);
			}
			else
			{
				data = new unsigned char[POTHigh * POTWide * 3];
				memset(data, 0, POTHigh * POTWide * 3);
				
				unsigned char* pPixelData = (unsigned char*) tempData;
				unsigned char* pTargetData = (unsigned char*) data;
				
				int imageHeight = this->getHeight();
				for(int y = 0; y < imageHeight; ++y)
				{
					memcpy(pTargetData+POTWide*3*y, pPixelData+(this->getWidth())*3*y, (this->getWidth())*3);
				}
			}
			break;   
		default:
			CCAssert(0, "Invalid pixel format");
	}
	
	// Repack the pixel data into the right format
	
	if(pixelFormat == kCCTexture2DPixelFormat_RGB565) {
		//Convert "RRRRRRRRRGGGGGGGGBBBBBBBBAAAAAAAA" to "RRRRRGGGGGGBBBBB"
		tempData = new unsigned char[POTHigh * POTWide * 2];
		inPixel32 = (unsigned int*)data;
		outPixel16 = (unsigned short*)tempData;
		
		unsigned int length = POTWide * POTHigh;
		for(unsigned int i = 0; i < length; ++i, ++inPixel32)
		{
			*outPixel16++ = 
			((((*inPixel32 >> 0) & 0xFF) >> 3) << 11) |  // R
			((((*inPixel32 >> 8) & 0xFF) >> 2) << 5) |   // G
			((((*inPixel32 >> 16) & 0xFF) >> 3) << 0);   // B
		}
		
		delete [] data;
		data = tempData;
	}
	else if (pixelFormat == kCCTexture2DPixelFormat_RGBA4444) {
		//Convert "RRRRRRRRRGGGGGGGGBBBBBBBBAAAAAAAA" to "RRRRGGGGBBBBAAAA"
		tempData = new unsigned char[POTHigh * POTWide * 2];
		inPixel32 = (unsigned int*)data;
		outPixel16 = (unsigned short*)tempData;
		
		unsigned int length = POTWide * POTHigh;
		for(unsigned int i = 0; i < length; ++i, ++inPixel32)
		{
			*outPixel16++ = 
			((((*inPixel32 >> 0) & 0xFF) >> 4) << 12) | // R
			((((*inPixel32 >> 8) & 0xFF) >> 4) << 8) | // G
			((((*inPixel32 >> 16) & 0xFF) >> 4) << 4) | // B
			((((*inPixel32 >> 24) & 0xFF) >> 4) << 0); // A
		}
		
		delete [] data;
		data = tempData;
	}
	else if (pixelFormat == kCCTexture2DPixelFormat_RGB5A1) {
		//Convert "RRRRRRRRRGGGGGGGGBBBBBBBBAAAAAAAA" to "RRRRRGGGGGBBBBBA"
		tempData = new unsigned char[POTHigh * POTWide * 2];
		inPixel32 = (unsigned int*)data;
		outPixel16 = (unsigned short*)tempData;
		
		unsigned int length = POTWide * POTHigh;
		for(unsigned int i = 0; i < length; ++i, ++inPixel32)
		{
			*outPixel16++ = 
			((((*inPixel32 >> 0) & 0xFF) >> 3) << 11) | // R
			((((*inPixel32 >> 8) & 0xFF) >> 3) << 6) | // G
			((((*inPixel32 >> 16) & 0xFF) >> 3) << 1) | // B
			((((*inPixel32 >> 24) & 0xFF) >> 7) << 0); // A
		}
		
		delete []data;
		data = tempData;
	}
	else if (pixelFormat == kCCTexture2DPixelFormat_A8)
	{
		// fix me, how to convert to A8
		pixelFormat = kCCTexture2DPixelFormat_RGBA8888;
		
		//
		//The code can not work, how to convert to A8?
		//
		//tempData = new unsigned char[POTHigh * POTWide];
		//inPixel32 = (unsigned int*)data;
		//outPixel8 = tempData;
		 
		//unsigned int length = POTWide * POTHigh;
		//for(unsigned int i = 0; i < length; ++i, ++inPixel32)
		//{
		//    *outPixel8++ = (*inPixel32 >> 24) & 0xFF;
		//}
		 
		//delete []data;
		//data = tempData;
		 
	}
	
	if (data)
	{
		CC_SAFE_DELETE_ARRAY(m_pData);
		m_pData = data;
	}
	return true;	
}
*/

//bool CCImage::initWithImageData(void * pData, int nDataLen, EImageFormat eFmt/* = eSrcFmtPng*/)
bool CCImage::initWithImageData(void * pData, 
                           int nDataLen, 
                           EImageFormat eFmt,
                           int nWidth,
                           int nHeight,
                           int nBitsPerComponent)
{
    bool bRet = false;
    tImageInfo info = {0};
    do 
    {
        CC_BREAK_IF(! pData || nDataLen <= 0);
        
        if (eFmt == kFmtRawData)
        {
            bRet = _initWithRawData(pData, nDataLen, nWidth, nHeight, nBitsPerComponent, false);
        }
        else if (eFmt == kFmtWebp)
        {
            bRet = _initWithWebpData(pData, nDataLen);
        }
        else
        {
            bRet = _initWithData(pData, nDataLen, &info, 1.0f, 1.0f);//m_dScaleX, m_dScaleY);
            if (bRet)
            {
                m_nHeight = (short)info.height;
                m_nWidth = (short)info.width;
                m_nBitsPerComponent = info.bitsPerComponent;
                if (eFmt == kFmtJpg)
                {
                    m_bHasAlpha = true;
                    m_bPreMulti = false;
                }
                else
                {
                    m_bHasAlpha = info.hasAlpha;
                    m_bPreMulti = info.isPremultipliedAlpha;
                }
                m_pData = info.data;
            }
        }
    } while (0);
	
    return bRet;
}

bool CCImage::_initWithRawData(void *pData, int nDatalen, int nWidth, int nHeight, int nBitsPerComponent, bool bPreMulti)
{
    bool bRet = false;
    do
    {
        CC_BREAK_IF(0 == nWidth || 0 == nHeight);
        
        m_nBitsPerComponent = nBitsPerComponent;
        m_nHeight   = (short)nHeight;
        m_nWidth    = (short)nWidth;
        m_bHasAlpha = true;
        
        // only RGBA8888 supported
        int nBytesPerComponent = 4;
        int nSize = nHeight * nWidth * nBytesPerComponent;
        m_pData = new unsigned char[nSize];
        CC_BREAK_IF(! m_pData);
        memcpy(m_pData, pData, nSize);
        
        bRet = true;
    } while (0);
    return bRet;
}

bool CCImage::initWithStringShadowStroke(
                                         const char * pText,
                                         int         nWidth ,
                                         int         nHeight ,
                                         ETextAlign eAlignMask ,
                                         const char * pFontName ,
                                         int         nSize ,
                                         float       textTintR,
                                         float       textTintG,
                                         float       textTintB,
                                         bool shadow,
                                         float shadowOffsetX,
                                         float shadowOffsetY,
                                         float shadowOpacity,
                                         float shadowBlur,
                                         bool  stroke,
                                         float strokeR,
                                         float strokeG,
                                         float strokeB,
                                         float strokeSize)
{
    tImageInfo info = {0};
    info.width                  = nWidth;
    info.height                 = nHeight;
    info.hasShadow              = shadow;
    info.shadowOffset.width     = shadowOffsetX;
    info.shadowOffset.height    = shadowOffsetY;
    info.shadowBlur             = shadowBlur;
    info.shadowOpacity          = shadowOpacity;
    info.hasStroke              =  stroke;
    info.strokeColorR           =  strokeR;
    info.strokeColorG           = strokeG;
    info.strokeColorB           = strokeB;
    info.strokeSize             = strokeSize;
    info.tintColorR             = textTintR;
    info.tintColorG             = textTintG;
    info.tintColorB             = textTintB;
    
    
    if (! _initWithString(pText, eAlignMask, pFontName, nSize, &info))
    {
        return false;
    }
    m_nHeight = (short)info.height;
    m_nWidth = (short)info.width;
    m_nBitsPerComponent = info.bitsPerComponent;
    m_bHasAlpha = info.hasAlpha;
    m_bPreMulti = info.isPremultipliedAlpha;
    m_pData = info.data;
    
    return true;
}

bool CCImage::initWithString(
	const char *    pText, 
	int             nWidth, 
	int             nHeight,
	ETextAlign      eAlignMask,
	const char *    pFontName,
	int             nSize)
{
    tImageInfo info = {0};
    info.width = nWidth;
    info.height = nHeight;
	
    if (! _initWithString(pText, eAlignMask, pFontName, nSize, &info)) //pStrokeColor))
    {
        return false;
    }
    m_nHeight = (short)info.height;
    m_nWidth = (short)info.width;
    m_nBitsPerComponent = info.bitsPerComponent;
    m_bHasAlpha = info.hasAlpha;
    m_bPreMulti = info.isPremultipliedAlpha;
	if (m_pData) {
		CC_SAFE_DELETE_ARRAY(m_pData);
	}
    m_pData = info.data;

    return true;
}

void CGImageWriteToFile(CGImageRef image, NSString *path, const CFStringRef type) {
    CFURLRef url = (CFURLRef)[NSURL fileURLWithPath:path];
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL(url, type, 1, NULL);
    CGImageDestinationAddImage(destination, image, nil);
    
    if (!CGImageDestinationFinalize(destination)) {
        NSLog(@"Failed to write image to %@", path);
    }
    
    CFRelease(destination);
}

bool CCImage::saveToFile(const char *pszFilePath, bool bIsToRGB)
{
    bool saveToPNG = false;
    bool needToCopyPixels = false;
    std::string filePath(pszFilePath);
    if (std::string::npos != filePath.find(".png"))
    {
        saveToPNG = true;
    }

    int bitsPerComponent = 8;
    int bitsPerPixel = m_bHasAlpha ? 32 : 24;
    if ((! saveToPNG) || bIsToRGB)
    {
        bitsPerPixel = 24;
    }

    int bytesPerRow    = (bitsPerPixel/8) * m_nWidth;
    int myDataLength = bytesPerRow * m_nHeight;

    unsigned char *pixels    = m_pData;

    // The data has alpha channel, and want to save it with an RGB png file,
    // or want to save as jpg,  remove the alpha channel.
    if ((saveToPNG && m_bHasAlpha && bIsToRGB)
       || (! saveToPNG))
    {
        pixels = new unsigned char[myDataLength];

        for (int i = 0; i < m_nHeight; ++i)
        {
            for (int j = 0; j < m_nWidth; ++j)
            {
                pixels[(i * m_nWidth + j) * 3] = m_pData[(i * m_nWidth + j) * 4];
                pixels[(i * m_nWidth + j) * 3 + 1] = m_pData[(i * m_nWidth + j) * 4 + 1];
                pixels[(i * m_nWidth + j) * 3 + 2] = m_pData[(i * m_nWidth + j) * 4 + 2];
            }
        }

        needToCopyPixels = true;
    }

    // make data provider with data.
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
    if (saveToPNG && m_bHasAlpha && (! bIsToRGB))
    {
        bitmapInfo |= kCGImageAlphaPremultipliedLast;
    }
    CGDataProviderRef provider        = CGDataProviderCreateWithData(NULL, pixels, myDataLength, NULL);
    CGColorSpaceRef colorSpaceRef    = CGColorSpaceCreateDeviceRGB();
    CGImageRef iref                    = CGImageCreate(m_nWidth, m_nHeight,
                                                        bitsPerComponent, bitsPerPixel, bytesPerRow,
                                                        colorSpaceRef, bitmapInfo, provider,
                                                        NULL, false,
                                                        kCGRenderingIntentDefault);


    if (saveToPNG)
    {
        CGImageWriteToFile(iref,[NSString stringWithUTF8String:pszFilePath], kUTTypePNG);
    }
    else
    {
        CGImageWriteToFile(iref,[NSString stringWithUTF8String:pszFilePath], kUTTypeJPEG);
    }

    CGImageRelease(iref);
    CGColorSpaceRelease(colorSpaceRef);
    CGDataProviderRelease(provider);
    
    
    if (needToCopyPixels)
    {
        delete [] pixels;
    }

    return true;
}



NS_CC_END

