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

/**
 * @file ZGVirtualMemory.c
 * @brief Implementation of Virtual Memory Interface for Bit Slicer
 *
 * This file implements the functions declared in ZGVirtualMemory.h, providing
 * a C interface for virtual memory operations in macOS. The implementation
 * wraps Mach kernel functions for memory manipulation, handling error cases
 * and providing a simplified interface.
 *
 * Implementation Overview:
 * -----------------------
 * The implementation follows these general patterns:
 *
 * 1. Task/Process Management:
 *    - Get task ports for processes
 *    - Manage port references
 *    - Suspend/resume tasks
 *
 * 2. Memory Operations:
 *    - Allocate/deallocate memory
 *    - Read/write memory with protection handling
 *    - Query memory regions and protection
 *
 * 3. Protection Handling:
 *    - Special handling for executable memory on ARM64
 *    - Temporary protection changes for writing
 *
 * Most functions return a boolean indicating success or failure, with
 * the actual work being done by Mach kernel functions.
 */

#include "ZGVirtualMemory.h"
#include <mach/mach_init.h>
#include <mach/mach_vm.h>
#include <mach/task.h>
#include <mach/mach_port.h>
#include <stdlib.h>

#include <TargetConditionals.h>

/**
 * @brief Get a task port for a process ID
 *
 * This function uses the Mach kernel's task_for_pid() function to get a task port
 * for the specified process ID. The task port is a reference to the process's
 * address space and allows for memory operations on that process.
 *
 * @param processID The process ID to get a task port for
 * @param processTask Pointer to store the resulting task port
 * @return true if successful, false otherwise
 */
bool ZGTaskForPID(int processID, ZGMemoryMap *processTask)
{
	return (task_for_pid(current_task(), processID, processTask) == KERN_SUCCESS);
}

/**
 * @brief Deallocate a task port
 *
 * This function deallocates a task port reference using the Mach kernel's
 * mach_port_deallocate() function. This should be called when finished with
 * a task port to prevent resource leaks.
 *
 * @param processTask The task port to deallocate
 * @return true if successful, false otherwise
 */
bool ZGDeallocatePort(ZGMemoryMap processTask)
{
	return (mach_port_deallocate(mach_task_self(), processTask) == KERN_SUCCESS);
}

/**
 * @brief Modify the reference count of a port's send right
 *
 * This function modifies the reference count of a port's send right using
 * the Mach kernel's mach_port_mod_refs() function. This is used for managing
 * port references in complex scenarios.
 *
 * @param processTask The task port to modify
 * @param delta The change to apply to the reference count
 * @return true if successful, false otherwise
 */
bool ZGSetPortSendRightReferenceCountByDelta(ZGMemoryMap processTask, mach_port_delta_t delta)
{
	return (mach_port_mod_refs(mach_task_self(), processTask, MACH_PORT_RIGHT_SEND, delta) == KERN_SUCCESS);
}

/**
 * @brief Get the process ID for a task port
 *
 * This function uses the Mach kernel's pid_for_task() function to get the
 * process ID associated with a task port.
 *
 * @param processTask The task port to query
 * @param processID Pointer to store the resulting process ID
 * @return true if successful, false otherwise
 */
bool ZGPIDForTask(ZGMemoryMap processTask, int *processID)
{
	return (pid_for_task(processTask, processID) == KERN_SUCCESS);
}

/**
 * @brief Get the page size for a task
 *
 * This function uses the Mach kernel's host_page_size() function to get the
 * page size for the specified task. The page size is the minimum unit of
 * memory allocation in virtual memory.
 *
 * @param processTask The task port to query
 * @param pageSize Pointer to store the resulting page size
 * @return true if successful, false otherwise
 */
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

/**
 * @brief Allocate memory in a process
 *
 * This function uses the Mach kernel's mach_vm_allocate() function to allocate
 * memory in the specified process. The VM_FLAGS_ANYWHERE flag allows the kernel
 * to choose any available address for the allocation.
 *
 * @param processTask The task port of the process
 * @param address Pointer to store the resulting address (input value is ignored)
 * @param size The size of memory to allocate in bytes
 * @return true if successful, false otherwise
 */
bool ZGAllocateMemory(ZGMemoryMap processTask, ZGMemoryAddress *address, ZGMemorySize size)
{
	return (mach_vm_allocate(processTask, address, size, VM_FLAGS_ANYWHERE) == KERN_SUCCESS);
}

/**
 * @brief Deallocate memory in a process
 *
 * This function uses the Mach kernel's mach_vm_deallocate() function to deallocate
 * memory in the specified process.
 *
 * @param processTask The task port of the process
 * @param address The starting address of the memory to deallocate
 * @param size The size of memory to deallocate in bytes
 * @return true if successful, false otherwise
 */
bool ZGDeallocateMemory(ZGMemoryMap processTask, ZGMemoryAddress address, ZGMemorySize size)
{
	return (mach_vm_deallocate(processTask, address, size) == KERN_SUCCESS);
}

/**
 * @brief Read bytes from a process's memory
 *
 * This function allocates a buffer and reads memory from the specified address
 * in the target process. It uses mach_vm_read_overwrite() instead of mach_vm_read()
 * to handle large buffer sizes that may span multiple pages.
 *
 * Memory Reading Process:
 * 1. Allocate a buffer of the requested size
 * 2. Read memory from the target process into the buffer
 * 3. Return the buffer to the caller (who must free it with ZGFreeBytes)
 *
 * @param processTask The task port of the process
 * @param address The address to read from
 * @param bytes Pointer to store the resulting bytes
 * @param size On input, the number of bytes to read; on output, the number of bytes actually read
 * @return true if successful, false otherwise
 */
bool ZGReadBytes(ZGMemoryMap processTask, ZGMemoryAddress address, void **bytes, ZGMemorySize *size)
{
	ZGMemorySize requestedSize = *size;
	void *data = calloc(1, requestedSize);
	if (data == NULL)
	{
		return false;
	}
	*bytes = data;

	// mach_vm_read() may cause issues when reading multiple pages
	// Let mach_vm_read_overwrite() handle the correct logic for us when requesting a large buffer size
	if (mach_vm_read_overwrite(processTask, address, requestedSize, (mach_vm_address_t)data, size) == KERN_SUCCESS)
	{
		return true;
	}
	else
	{
		free(data);
		return false;
	}
}

/**
 * @brief Free memory allocated by ZGReadBytes()
 *
 * This function frees memory that was allocated by ZGReadBytes().
 * The size parameter is unused but kept for API consistency.
 *
 * @param bytes The memory to free
 * @param size The size of the memory (unused)
 * @return true if successful, false otherwise
 */
bool ZGFreeBytes(void *bytes, ZGMemorySize __unused size)
{
	free(bytes);
	return true;
}

/**
 * @brief Write bytes to a process's memory
 *
 * This function writes memory to the specified address in the target process
 * using the Mach kernel's mach_vm_write() function. The memory must be writable
 * for this function to succeed.
 *
 * @param processTask The task port of the process
 * @param address The address to write to
 * @param bytes The bytes to write
 * @param size The number of bytes to write
 * @return true if successful, false otherwise
 */
bool ZGWriteBytes(ZGMemoryMap processTask, ZGMemoryAddress address, const void *bytes, ZGMemorySize size)
{
	return (mach_vm_write(processTask, address, (vm_offset_t)bytes, (mach_msg_type_number_t)size) == KERN_SUCCESS);
}

/**
 * @brief Helper function for writing bytes with protection handling
 *
 * This function handles the complex logic of writing to memory that may not be
 * writable or may be executable. It temporarily changes the memory protection
 * if needed, writes the bytes, and then optionally restores the original protection.
 *
 * Special handling for ARM64:
 * - On ARM64, memory cannot be both writable and executable at the same time
 * - If the memory is executable, we need to remove the execute permission and add write
 * - We also need to suspend the task while modifying executable memory
 *
 * @param processTask The task port of the process
 * @param address The address to write to
 * @param bytes The bytes to write
 * @param size The number of bytes to write
 * @param revertingBack Whether to revert the protection back to its original state
 * @return true if successful, false otherwise
 */
static bool ZGWriteBytesOverwritingProtectionAndRevertingBack(ZGMemoryMap processTask, ZGMemoryAddress address, const void *bytes, ZGMemorySize size, bool revertingBack)
{
	ZGMemoryAddress protectionAddress = address;
	ZGMemorySize protectionSize = size;
	ZGMemoryProtection oldProtection = 0;

	// Get the current protection of the memory region
	if (!ZGMemoryProtectionInRegion(processTask, &protectionAddress, &protectionSize, &oldProtection))
	{
		return false;
	}

#if TARGET_CPU_ARM64
	// Check if write isn't present or if execute is present
	// For processes using a JIT (possibly only with Rosetta) it's possible both write and execute are enabled, but we can't write bytes
	// without both enabled
	bool needsToChangeProtection = ((oldProtection & VM_PROT_WRITE) == 0 || (oldProtection & VM_PROT_EXECUTE) != 0);
#else
	bool needsToChangeProtection = ((oldProtection & VM_PROT_WRITE) == 0);
#endif

	bool needsExecutableProtectionModified;
	if (needsToChangeProtection)
	{
		ZGMemoryProtection newProtection;
#if TARGET_CPU_ARM64
		if ((oldProtection & VM_PROT_EXECUTE) != 0)
		{
			// On ARM64, memory can't be both writable and executable
			// Remove execute permission and add write permission
			newProtection = (oldProtection & ~VM_PROT_EXECUTE) | VM_PROT_WRITE;
			needsExecutableProtectionModified = true;

			// Suspend the task while modifying executable memory
			ZGSuspendTask(processTask);
		}
		else
#endif
		{
			// Just add write permission
			newProtection = (oldProtection | VM_PROT_WRITE);
			needsExecutableProtectionModified = false;
		}

		// Change the protection to make it writable
		if (!ZGProtect(processTask, protectionAddress, protectionSize, newProtection))
		{
			if (needsExecutableProtectionModified)
			{
				ZGResumeTask(processTask);
			}
			return false;
		}
	}
	else
	{
		needsExecutableProtectionModified = false;
	}

	// Write the bytes
	bool success = ZGWriteBytes(processTask, address, bytes, size);

	// Re-protect the region back to the way it was if needed
	if ((revertingBack || needsExecutableProtectionModified) && needsToChangeProtection)
	{
		ZGProtect(processTask, protectionAddress, protectionSize, oldProtection);

		if (needsExecutableProtectionModified)
		{
			ZGResumeTask(processTask);
		}
	}

	return success;
}

/**
 * @brief Write bytes to a process's memory, temporarily changing protection if needed
 *
 * This function writes memory to the specified address in the target process,
 * temporarily changing the memory protection if needed to make it writable.
 * The original protection is not restored unless it involves executable memory.
 *
 * @param processTask The task port of the process
 * @param address The address to write to
 * @param bytes The bytes to write
 * @param size The number of bytes to write
 * @return true if successful, false otherwise
 */
bool ZGWriteBytesOverwritingProtection(ZGMemoryMap processTask, ZGMemoryAddress address, const void *bytes, ZGMemorySize size)
{
	return ZGWriteBytesOverwritingProtectionAndRevertingBack(processTask, address, bytes, size, false);
}

/**
 * @brief Write bytes to a process's memory, ignoring protection
 *
 * This function writes memory to the specified address in the target process,
 * temporarily changing the memory protection if needed to make it writable.
 * The original protection is always restored after writing.
 *
 * @param processTask The task port of the process
 * @param address The address to write to
 * @param bytes The bytes to write
 * @param size The number of bytes to write
 * @return true if successful, false otherwise
 */
bool ZGWriteBytesIgnoringProtection(ZGMemoryMap processTask, ZGMemoryAddress address, const void *bytes, ZGMemorySize size)
{
	return ZGWriteBytesOverwritingProtectionAndRevertingBack(processTask, address, bytes, size, true);
}

/**
 * @brief Get basic information about a memory region
 *
 * This function uses the Mach kernel's mach_vm_region() function to get basic
 * information about a memory region in the specified process. The information
 * includes the region's protection, inheritance, and other basic attributes.
 *
 * @param processTask The task port of the process
 * @param address On input, the address to query; on output, the start of the region
 * @param size On output, the size of the region
 * @param regionInfo Pointer to store the resulting region information
 * @return true if successful, false otherwise
 */
bool ZGRegionInfo(ZGMemoryMap processTask, ZGMemoryAddress *address, ZGMemorySize *size, ZGMemoryBasicInfo *regionInfo)
{
	mach_port_t objectName = MACH_PORT_NULL;
	mach_msg_type_number_t regionInfoSize = VM_REGION_BASIC_INFO_COUNT_64;

	return mach_vm_region(processTask, address, size, VM_REGION_BASIC_INFO_64, (vm_region_info_t)regionInfo, &regionInfoSize, &objectName) == KERN_SUCCESS;
}

/**
 * @brief Get extended information about a memory region
 *
 * This function uses the Mach kernel's mach_vm_region() function to get extended
 * information about a memory region in the specified process. The extended
 * information includes additional details beyond the basic information.
 *
 * @param processTask The task port of the process
 * @param address On input, the address to query; on output, the start of the region
 * @param size On output, the size of the region
 * @param regionInfo Pointer to store the resulting extended region information
 * @return true if successful, false otherwise
 */
bool ZGRegionExtendedInfo(ZGMemoryMap processTask, ZGMemoryAddress *address, ZGMemorySize *size, ZGMemoryExtendedInfo *regionInfo)
{
	mach_port_t objectName = MACH_PORT_NULL;
	mach_msg_type_number_t regionInfoSize = VM_REGION_EXTENDED_INFO_COUNT;

	return mach_vm_region(processTask, address, size, VM_REGION_EXTENDED_INFO, (vm_region_info_t)regionInfo, &regionInfoSize, &objectName) == KERN_SUCCESS;
}

/**
 * @brief Get submap information about a memory region
 *
 * This function uses the Mach kernel's mach_vm_region_recurse() function to get
 * submap information about a memory region in the specified process. It recursively
 * traverses submaps until it finds a non-submap region.
 *
 * Memory Submaps:
 * --------------
 * In Mach VM, memory regions can be organized hierarchically with submaps.
 * This function traverses this hierarchy to find the actual memory region.
 *
 * @param processTask The task port of the process
 * @param address On input, the address to query; on output, the start of the region
 * @param size On output, the size of the region
 * @param regionInfo Pointer to store the resulting submap region information
 * @return true if successful, false otherwise
 */
bool ZGRegionSubmapInfo(ZGMemoryMap processTask, ZGMemoryAddress *address, ZGMemorySize *size, ZGMemorySubmapInfo *regionInfo)
{
	bool success = true;
	mach_msg_type_number_t infoCount;
	natural_t depth = 0;

	// Recursively traverse submaps until we find a non-submap region
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

/**
 * @brief Get the memory protection of a region
 *
 * This function gets the memory protection of a region in the specified process.
 * It uses ZGRegionInfo() to get the basic information about the region, then
 * extracts the protection from that information.
 *
 * @param processTask The task port of the process
 * @param address On input, the address to query; on output, the start of the region
 * @param size On output, the size of the region
 * @param memoryProtection Pointer to store the resulting memory protection
 * @return true if successful, false otherwise
 */
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

/**
 * @brief Change the memory protection of a region
 *
 * This function uses the Mach kernel's mach_vm_protect() function to change the
 * memory protection of a region in the specified process. If the initial attempt
 * fails, it tries again with the VM_PROT_COPY flag, which can help in certain cases.
 *
 * Protection Flags:
 * ----------------
 * VM_PROT_NONE    = 0x00 (---)
 * VM_PROT_READ    = 0x01 (r--)
 * VM_PROT_WRITE   = 0x02 (-w-)
 * VM_PROT_EXECUTE = 0x04 (--x)
 *
 * @param processTask The task port of the process
 * @param address The starting address of the region
 * @param size The size of the region
 * @param protection The new protection to apply
 * @return true if successful, false otherwise
 */
bool ZGProtect(ZGMemoryMap processTask, ZGMemoryAddress address, ZGMemorySize size, ZGMemoryProtection protection)
{
	// First try without VM_PROT_COPY
	kern_return_t initialResult = mach_vm_protect(processTask, address, size, FALSE, protection);
	kern_return_t finalResult;

	if (initialResult != KERN_SUCCESS)
	{
		// If that fails, try with VM_PROT_COPY
		// VM_PROT_COPY creates a copy-on-write mapping, which can help in some cases
		finalResult = mach_vm_protect(processTask, address, size, FALSE, protection | VM_PROT_COPY);
	}
	else
	{
		finalResult = initialResult;
	}

	return (finalResult == KERN_SUCCESS);
}

/**
 * @brief Get the suspend count of a task
 *
 * This function uses the Mach kernel's task_info() function to get information
 * about the specified task, including its suspend count. The suspend count
 * indicates how many times the task has been suspended.
 *
 * Task Suspension:
 * ---------------
 * A task's suspend count starts at 0 (running).
 * Each call to ZGSuspendTask() increments the count.
 * Each call to ZGResumeTask() decrements the count.
 * The task is running only when the count is 0.
 *
 * @param processTask The task port of the process
 * @param suspendCount Pointer to store the resulting suspend count
 * @return true if successful, false otherwise
 */
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

/**
 * @brief Suspend a task
 *
 * This function uses the Mach kernel's task_suspend() function to suspend
 * the specified task. Suspending a task stops all its threads from executing.
 * Each call to this function increments the task's suspend count.
 *
 * @param processTask The task port of the process to suspend
 * @return true if successful, false otherwise
 *
 * @note A suspended task can be resumed with ZGResumeTask()
 */
bool ZGSuspendTask(ZGMemoryMap processTask)
{
	return (task_suspend(processTask) == KERN_SUCCESS);
}

/**
 * @brief Resume a task
 *
 * This function uses the Mach kernel's task_resume() function to resume
 * the specified task. Resuming a task allows its threads to continue executing.
 * Each call to this function decrements the task's suspend count.
 *
 * @param processTask The task port of the process to resume
 * @return true if successful, false otherwise
 *
 * @note This only has an effect if the task was previously suspended with ZGSuspendTask()
 */
bool ZGResumeTask(ZGMemoryMap processTask)
{
	return (task_resume(processTask) == KERN_SUCCESS);
}
