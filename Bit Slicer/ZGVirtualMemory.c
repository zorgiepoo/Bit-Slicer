/*
 * Copyright (c) 2012 Mayur Pawashe
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * Redistributions of source code must retain the above copyright notice,
 * this list of conditions and the following disclaimer.
 *
 * Redistributions in binary form must reproduce the above copyright
 * notice, this list of conditions and the following disclaimer in the
 * documentation and/or other materials provided with the distribution.
 *
 * Neither the name of the project's author nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
 * TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include "ZGVirtualMemory.h"
#include <mach/mach_init.h>
#include <mach/mach_vm.h>
#include <mach/task.h>
#include <mach/mach_port.h>

bool ZGTaskForPID(int processID, ZGMemoryMap *processTask)
{
	return (task_for_pid(current_task(), processID, processTask) == KERN_SUCCESS);
}

bool ZGDeallocatePort(ZGMemoryMap processTask)
{
	return (mach_port_deallocate(mach_task_self(), processTask) == KERN_SUCCESS);
}

bool ZGSetPortSendRightReferenceCountByDelta(ZGMemoryMap processTask, mach_port_delta_t delta)
{
	return (mach_port_mod_refs(mach_task_self(), processTask, MACH_PORT_RIGHT_SEND, delta) == KERN_SUCCESS);
}

bool ZGPIDForTask(ZGMemoryMap processTask, int *processID)
{
	return (pid_for_task(processTask, processID) == KERN_SUCCESS);
}

bool ZGPageSize(ZGMemoryMap processTask, ZGMemorySize *pageSize)
{
	vm_size_t tempPageSize;
	kern_return_t retValue = host_page_size(processTask, &tempPageSize);
	if (retValue == KERN_SUCCESS)
	{
		*pageSize = tempPageSize;
	}
	return (retValue == KERN_SUCCESS);
}

bool ZGAllocateMemory(ZGMemoryMap processTask, ZGMemoryAddress *address, ZGMemorySize size)
{
	return (mach_vm_allocate(processTask, address, size, VM_FLAGS_ANYWHERE) == KERN_SUCCESS);
}

bool ZGDeallocateMemory(ZGMemoryMap processTask, ZGMemoryAddress address, ZGMemorySize size)
{
	return (mach_vm_deallocate(processTask, address, size) == KERN_SUCCESS);
}

bool ZGReadBytes(ZGMemoryMap processTask, ZGMemoryAddress address, void **bytes, ZGMemorySize *size)
{
	ZGMemorySize originalSize = *size;
	vm_offset_t dataPointer = 0;
	mach_msg_type_number_t dataSize = 0;
	bool success = false;
	if (mach_vm_read(processTask, address, originalSize, &dataPointer, &dataSize) == KERN_SUCCESS)
	{
		success = true;
		*bytes = (void *)dataPointer;
		*size = dataSize;
	}
	
	return success;
}

bool ZGFreeBytes(const void *bytes, ZGMemorySize size)
{
	return mach_vm_deallocate(current_task(), (vm_offset_t)bytes, size) == KERN_SUCCESS;
}

bool ZGWriteBytes(ZGMemoryMap processTask, ZGMemoryAddress address, const void *bytes, ZGMemorySize size)
{
	return (mach_vm_write(processTask, address, (vm_offset_t)bytes, (mach_msg_type_number_t)size) == KERN_SUCCESS);
}

static bool ZGWriteBytesOverwritingProtectionAndRevertingBack(ZGMemoryMap processTask, ZGMemoryAddress address, const void *bytes, ZGMemorySize size, bool revertingBack)
{
	ZGMemoryAddress protectionAddress = address;
	ZGMemorySize protectionSize = size;
	ZGMemoryProtection oldProtection = 0;
	
	if (!ZGMemoryProtectionInRegion(processTask, &protectionAddress, &protectionSize, &oldProtection))
	{
		return false;
	}
	
	if (!(oldProtection & VM_PROT_WRITE))
	{
		if (!ZGProtect(processTask, protectionAddress, protectionSize, oldProtection | VM_PROT_WRITE))
		{
			return false;
		}
	}
	
	bool success = ZGWriteBytes(processTask, address, bytes, size);
	
	// Re-protect the region back to the way it was
	if (revertingBack && !(oldProtection & VM_PROT_WRITE))
	{
		ZGProtect(processTask, protectionAddress, protectionSize, oldProtection);
	}
	
	return success;
}

bool ZGWriteBytesOverwritingProtection(ZGMemoryMap processTask, ZGMemoryAddress address, const void *bytes, ZGMemorySize size)
{
	return ZGWriteBytesOverwritingProtectionAndRevertingBack(processTask, address, bytes, size, false);
}


bool ZGWriteBytesIgnoringProtection(ZGMemoryMap processTask, ZGMemoryAddress address, const void *bytes, ZGMemorySize size)
{
	return ZGWriteBytesOverwritingProtectionAndRevertingBack(processTask, address, bytes, size, true);
}

bool ZGRegionInfo(ZGMemoryMap processTask, ZGMemoryAddress *address, ZGMemorySize *size, ZGMemoryBasicInfo *regionInfo)
{
	mach_port_t objectName = MACH_PORT_NULL;
	mach_msg_type_number_t regionInfoSize = VM_REGION_BASIC_INFO_COUNT_64;
	
	return mach_vm_region(processTask, address, size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)regionInfo, &regionInfoSize, &objectName) == KERN_SUCCESS;
}

bool ZGRegionSubmapInfo(ZGMemoryMap processTask, ZGMemoryAddress *address, ZGMemorySize *size, ZGMemorySubmapInfo *regionInfo)
{
	bool success = true;
	mach_msg_type_number_t infoCount;
	natural_t depth = 0;
	
	while (true)
	{
		infoCount = VM_REGION_SUBMAP_INFO_COUNT_64;
		success = success && mach_vm_region_recurse(processTask, address, size, &depth, (vm_region_recurse_info_t)regionInfo, &infoCount) == KERN_SUCCESS;
		if (!success || !regionInfo->is_submap)
		{
			break;
		}
		depth++;
	}
	return success;
}

bool ZGMemoryProtectionInRegion(ZGMemoryMap processTask, ZGMemoryAddress *address, ZGMemorySize *size, ZGMemoryProtection *memoryProtection)
{
	ZGMemoryBasicInfo regionInfo;
	if (ZGRegionInfo(processTask, address, size, &regionInfo))
	{
		*memoryProtection = regionInfo.protection;
		return true;
	}
	
	return false;
}

bool ZGProtect(ZGMemoryMap processTask, ZGMemoryAddress address, ZGMemorySize size, ZGMemoryProtection protection)
{
	return (mach_vm_protect(processTask, address, size, FALSE, protection) == KERN_SUCCESS);
}

bool ZGSuspendCount(ZGMemoryMap processTask, integer_t *suspendCount)
{
	*suspendCount = -1;
	task_basic_info_64_data_t taskInfo;
	mach_msg_type_number_t count = TASK_BASIC_INFO_64_COUNT;
	
	bool success = (task_info(processTask, TASK_BASIC_INFO_64, (task_info_t)&taskInfo, &count) == KERN_SUCCESS);
	if (success)
	{
		*suspendCount = taskInfo.suspend_count;
	}
	
	return success;
}

bool ZGSuspendTask(ZGMemoryMap processTask)
{
	return (task_suspend(processTask) == KERN_SUCCESS);
}

bool ZGResumeTask(ZGMemoryMap processTask)
{
	return (task_resume(processTask) == KERN_SUCCESS);
}
