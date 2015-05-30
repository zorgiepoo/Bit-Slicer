//
//  ZGVirtualMemoryStringReading.m
//  Bit Slicer
//
//  Created by Mayur Pawashe on 5/29/15.
//
//

#import "ZGVirtualMemoryStringReading.h"
#import "ZGVirtualMemory.h"

ZGMemorySize ZGGetStringSize(ZGMemoryMap processTask, ZGMemoryAddress address, ZGVariableType dataType, ZGMemorySize oldSize, ZGMemorySize maxStringSizeLimit)
{
	ZGMemorySize totalSize = 0;
	
	ZGMemorySize characterSize = (dataType == ZGString8) ? sizeof(char) : sizeof(unichar);
	void *buffer = NULL;
	
	if (dataType == ZGString16 && oldSize % 2 != 0)
	{
		oldSize--;
	}
	
	BOOL shouldUseOldSize = (oldSize >= characterSize);
	
	while (YES)
	{
		BOOL shouldBreak = NO;
		ZGMemorySize outputtedSize = shouldUseOldSize ? oldSize : characterSize;
		
		BOOL couldReadBytes = ZGReadBytes(processTask, address, &buffer, &outputtedSize);
		if (!couldReadBytes && shouldUseOldSize)
		{
			shouldUseOldSize = NO;
			continue;
		}
		
		if (couldReadBytes)
		{
			ZGMemorySize numberOfCharacters = outputtedSize / characterSize;
			if (dataType == ZGString16 && outputtedSize % 2 != 0 && numberOfCharacters > 0)
			{
				numberOfCharacters--;
				shouldBreak = YES;
			}
			
			for (ZGMemorySize characterCounter = 0; characterCounter < numberOfCharacters; characterCounter++)
			{
				if ((dataType == ZGString8 && ((char *)buffer)[characterCounter] == 0) || (dataType == ZGString16 && ((unichar *)buffer)[characterCounter] == 0))
				{
					shouldBreak = YES;
					break;
				}
				
				totalSize += characterSize;
			}
			
			ZGFreeBytes(buffer, outputtedSize);
			
			if (maxStringSizeLimit > 0 && totalSize >= maxStringSizeLimit)
			{
				totalSize = maxStringSizeLimit;
				shouldBreak = YES;
			}
			
			if (dataType == ZGString16)
			{
				outputtedSize = numberOfCharacters * characterSize;
			}
		}
		else
		{
			shouldBreak = YES;
		}
		
		if (shouldBreak)
		{
			break;
		}
		
		address += outputtedSize;
	}
	
	return totalSize;
}
