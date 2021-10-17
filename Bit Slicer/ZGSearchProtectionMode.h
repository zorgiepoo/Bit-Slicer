//
//  ZGSearchProtectionMode.h
//  ZGSearchProtectionMode
//
//  Created by Mayur Pawashe on 10/16/21.
//

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif
#include "ZGMemoryTypes.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ZGProtectionMode)
{
	ZGProtectionAll,
	ZGProtectionWrite,
	ZGProtectionExecute
};

BOOL ZGMemoryProtectionMatchesProtectionMode(ZGMemoryProtection memoryProtection, ZGProtectionMode protectionMode);

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif
