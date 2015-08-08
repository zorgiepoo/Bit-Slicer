/* Copyright (c) 2005-2011, Peter Ammon
 * All rights reserved.
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *     * Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above copyright
 *       notice, this list of conditions and the following disclaimer in the
 *       documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE REGENTS AND CONTRIBUTORS BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include "HFByteArray_FindReplace.h"

// This portion of code is mostly stripped from a function in Hex Fiend's framework; it's wicked fast.
void ZGPrepareBoyerMooreSearch(const unsigned char *needle, const unsigned long needle_length, unsigned long *char_jump, unsigned long *match_jump)
{
	unsigned long *backup;
	unsigned long u, ua, ub;
	backup = match_jump + needle_length + 1;
	
	// heuristic #1 setup, simple text search
	for (u=0; u < sizeof char_jump / sizeof *char_jump; u++)
	{
		char_jump[u] = needle_length;
	}
	
	for (u = 0; u < needle_length; u++)
	{
		char_jump[(static_cast<unsigned char>(needle[u]))] = needle_length - u - 1;
	}
	
	// heuristic #2 setup, repeating pattern search
	for (u = 1; u <= needle_length; u++)
	{
		match_jump[u] = 2 * needle_length - u;
	}
	
	u = needle_length;
	ua = needle_length + 1;
	while (u > 0)
	{
		backup[u] = ua;
		while (ua <= needle_length && needle[u - 1] != needle[ua - 1])
		{
			if (match_jump[ua] > needle_length - u) match_jump[ua] = needle_length - u;
			ua = backup[ua];
		}
		u--; ua--;
	}
	
	for (u = 1; u <= ua; u++)
	{
		if (match_jump[u] > needle_length + ua - u) match_jump[u] = needle_length + ua - u;
	}
	
	ub = ua;
	while (ua <= needle_length)
	{
		ub = backup[ub];
		while (ua <= ub)
		{
			if (match_jump[ua] > ub - ua + needle_length)
			{
				match_jump[ua] = ub - ua + needle_length;
			}
			ua++;
		}
	}
}
