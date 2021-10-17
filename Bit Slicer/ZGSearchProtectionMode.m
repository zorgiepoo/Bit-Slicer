//
//  ZGSearchProtectionMode.m
//  ZGSearchProtectionMode
//
//  Created by Mayur Pawashe on 10/16/21.
//

#import "ZGSearchProtectionMode.h"

BOOL ZGMemoryProtectionMatchesProtectionMode(ZGMemoryProtection memoryProtection, ZGProtectionMode protectionMode)
{
	return ((protectionMode == ZGProtectionAll && memoryProtection & VM_PROT_READ) || (protectionMode == ZGProtectionWrite && memoryProtection & VM_PROT_WRITE) || (protectionMode == ZGProtectionExecute && memoryProtection & VM_PROT_EXECUTE));
}
