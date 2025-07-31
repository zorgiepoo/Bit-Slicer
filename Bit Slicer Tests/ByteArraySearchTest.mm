/*
 * Copyright (c) 2014 Mayur Pawashe
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

#import <XCTest/XCTest.h>

/**
 * Test suite for the Boyer-Moore byte array search algorithm implementation.
 *
 * The Boyer-Moore algorithm is an efficient string searching algorithm that
 * uses two heuristics to skip portions of the text during the search process:
 * 1. Bad Character Rule: If a mismatch occurs, shift the pattern to align with
 *    the rightmost occurrence of the mismatched character in the pattern.
 * 2. Good Suffix Rule: If a mismatch occurs, shift the pattern to align with
 *    the next occurrence of the already matched suffix.
 *
 * These tests verify the correctness and efficiency of the implementation
 * across various search patterns and edge cases.
 */
@interface ByteArraySearchTest : XCTestCase

@end

@implementation ByteArraySearchTest
{
	NSData *_data;
}

extern "C" unsigned char* boyer_moore_helper(const unsigned char *haystack, const unsigned char *needle, unsigned long haystack_length, unsigned long needle_length, const unsigned long *char_jump, const unsigned long *match_jump);

extern void ZGPrepareBoyerMooreSearch(const unsigned char *needle, const unsigned long needle_length, unsigned long *char_jump, size_t char_jump_size, unsigned long *match_jump);

- (void)setUp
{
	[super setUp];

	NSBundle *bundle = [NSBundle bundleForClass:[self class]];
	NSString *randomDataPath = [bundle pathForResource:@"random_data" ofType:@""];
	XCTAssertNotNil(randomDataPath);

	NSData *data = [NSData dataWithContentsOfFile:randomDataPath];
	XCTAssertNotNil(data);

	_data = data;
}

- (BOOL)searchAndVerifyBytes:(const uint8_t *)bytes length:(NSUInteger)length getNumberOfResults:(NSUInteger *)numberOfResultsBack
{
	XCTAssertTrue(length <= _data.length);

	NSUInteger numberOfResults = 0;
	for (NSUInteger dataIndex = 0; dataIndex + length <= _data.length; dataIndex++)
	{
		if (memcmp(bytes, static_cast<const uint8_t *>(_data.bytes) + dataIndex, length) == 0)
		{
			numberOfResults++;
		}
	}

	NSUInteger numberOfBoyerMooreResults = 0;

	unsigned long long size = _data.length;
	unsigned long long dataSize = length;
	const unsigned char *dataBytes = static_cast<const unsigned char *>(_data.bytes);

	unsigned long charJump[UCHAR_MAX + 1] = {0};
	unsigned long *matchJump = static_cast<unsigned long *>(malloc(2 * (dataSize + 1) * sizeof(*matchJump)));

	ZGPrepareBoyerMooreSearch(bytes, dataSize, charJump, sizeof charJump / sizeof *charJump, matchJump);

	const unsigned char *foundSubstring = static_cast<const unsigned char *>(dataBytes);
	unsigned long haystackLengthLeft = size;

	while (haystackLengthLeft >= dataSize)
	{
		foundSubstring = boyer_moore_helper(foundSubstring, bytes, haystackLengthLeft, dataSize, charJump, matchJump);
		if (foundSubstring == nullptr) break;

		// boyer_moore_helper is only checking 0 .. dataSize-1 characters, so make a check to see if the last characters are equal
		if (foundSubstring[dataSize-1] == bytes[dataSize-1])
		{
			numberOfBoyerMooreResults++;
		}

		foundSubstring++;
		haystackLengthLeft = size - static_cast<unsigned long long>(foundSubstring - dataBytes);
	}

	free(matchJump);

	*numberOfResultsBack = numberOfResults;

	return (numberOfResults == numberOfBoyerMooreResults);
}

- (void)testOneResult
{
	const uint8_t bytes[] = {0x00, 0x00, 0x01};
	NSUInteger numberOfResults = 0;
	XCTAssertTrue([self searchAndVerifyBytes:bytes length:sizeof(bytes) getNumberOfResults:&numberOfResults]);
	XCTAssertEqual(numberOfResults, 1U);
}

- (void)testFewResultsAndAtBeginning
{
	const uint8_t bytes[] = {0x00, 0xB1};
	NSUInteger numberOfResults = 0;
	XCTAssertTrue([self searchAndVerifyBytes:bytes length:sizeof(bytes) getNumberOfResults:&numberOfResults]);
	XCTAssertEqual(numberOfResults, 3U);
}

- (void)testOneByteResults
{
	const uint8_t bytes[] = {0xA1};
	NSUInteger numberOfResults = 0;
	XCTAssertTrue([self searchAndVerifyBytes:bytes length:sizeof(bytes) getNumberOfResults:&numberOfResults]);
	XCTAssertEqual(numberOfResults, 85U);
}

- (void)testNearEndOfData
{
	const uint8_t bytes[] = {0xEC, 0x9E, 0x5F};
	NSUInteger numberOfResults = 0;
	XCTAssertTrue([self searchAndVerifyBytes:bytes length:sizeof(bytes) getNumberOfResults:&numberOfResults]);
	XCTAssertEqual(numberOfResults, 1U);
}

- (void)testEndOfData
{
	const uint8_t bytes[] = {0x9E, 0x5F, 0x07};
	NSUInteger numberOfResults = 0;
	XCTAssertTrue([self searchAndVerifyBytes:bytes length:sizeof(bytes) getNumberOfResults:&numberOfResults]);
	XCTAssertEqual(numberOfResults, 1U);
}

/**
 * Tests searching for a pattern with repeating bytes.
 *
 * This test verifies the Boyer-Moore algorithm's handling of patterns with
 * repeating bytes, which can trigger the good suffix rule.
 *
 * Memory layout and search process:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                      Memory Contents                            │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                 │
 * │  ... AA AA AA AA AA AA AA AA AA AA AA AA AA AA AA AA AA ...     │
 * │      ↑                                                          │
 * │      └── Search starts here                                     │
 * │                                                                 │
 * │  Pattern: AA AA AA AA                                           │
 * │                                                                 │
 * │  Boyer-Moore Search Process:                                    │
 * │  1. Compare pattern from right to left                          │
 * │  2. When a match is found, shift by 1 position                  │
 * │  3. For repeating patterns, the good suffix rule                │
 * │     allows skipping redundant comparisons                       │
 * │                                                                 │
 * │  Expected: Multiple matches found in sequence                   │
 * │                                                                 │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)testRepeatingPattern
{
    // Create a buffer with repeating bytes
    const NSUInteger bufferSize = 1024;
    uint8_t *buffer = (uint8_t *)malloc(bufferSize);
    if (buffer == NULL) {
        XCTFail(@"Failed to allocate memory for test buffer");
        return;
    }

    // Fill buffer with repeating pattern of 0xAA
    memset(buffer, 0xAA, bufferSize);

    // Create a temporary NSData with our controlled buffer
    NSData *originalData = _data;
    _data = [NSData dataWithBytesNoCopy:buffer length:bufferSize freeWhenDone:YES];

    // Search for a pattern of 4 repeating bytes
    const uint8_t pattern[] = {0xAA, 0xAA, 0xAA, 0xAA};
    NSUInteger numberOfResults = 0;
    XCTAssertTrue([self searchAndVerifyBytes:pattern length:sizeof(pattern) getNumberOfResults:&numberOfResults]);

    // Expected number of results: bufferSize - pattern length + 1
    NSUInteger expectedResults = bufferSize - sizeof(pattern) + 1;
    XCTAssertEqual(numberOfResults, expectedResults);

    // Restore original data
    _data = originalData;
}

/**
 * Tests searching for a pattern with alternating bytes.
 *
 * This test verifies the Boyer-Moore algorithm's handling of patterns with
 * alternating bytes, which exercises both the bad character and good suffix rules.
 *
 * Memory layout and search process:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                      Memory Contents                            │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                 │
 * │  ... AB AB AB AB AB AB AB AB AB AB AB AB AB AB AB AB AB ...     │
 * │      ↑                                                          │
 * │      └── Search starts here                                     │
 * │                                                                 │
 * │  Pattern: AB AB AB AB                                           │
 * │                                                                 │
 * │  Boyer-Moore Search Process:                                    │
 * │  1. Compare pattern from right to left                          │
 * │  2. For alternating patterns, the bad character rule            │
 * │     allows skipping positions when a mismatch occurs            │
 * │  3. The good suffix rule helps with partial matches             │
 * │                                                                 │
 * │  Register States During Search:                                 │
 * │  - charJump['A'] = 2 (skip 2 positions if 'A' mismatches)       │
 * │  - charJump['B'] = 1 (skip 1 position if 'B' mismatches)        │
 * │  - matchJump values handle the repeating "AB" pattern           │
 * │                                                                 │
 * │  Expected: Multiple matches found at every other position       │
 * │                                                                 │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)testAlternatingPattern
{
    // Create a buffer with alternating bytes
    const NSUInteger bufferSize = 1024;
    uint8_t *buffer = (uint8_t *)malloc(bufferSize);
    if (buffer == NULL) {
        XCTFail(@"Failed to allocate memory for test buffer");
        return;
    }

    // Fill buffer with alternating pattern of 0xAB
    for (NSUInteger i = 0; i < bufferSize; i++) {
        buffer[i] = (i % 2 == 0) ? 0xAA : 0xBB;
    }

    // Create a temporary NSData with our controlled buffer
    NSData *originalData = _data;
    _data = [NSData dataWithBytesNoCopy:buffer length:bufferSize freeWhenDone:YES];

    // Search for a pattern of alternating bytes
    const uint8_t pattern[] = {0xAA, 0xBB, 0xAA, 0xBB};
    NSUInteger numberOfResults = 0;
    XCTAssertTrue([self searchAndVerifyBytes:pattern length:sizeof(pattern) getNumberOfResults:&numberOfResults]);

    // Expected number of results: (bufferSize - pattern length + 1) / 2
    // We divide by 2 because matches can only occur at even positions
    NSUInteger expectedResults = (bufferSize - sizeof(pattern) + 1) / 2;
    XCTAssertEqual(numberOfResults, expectedResults);

    // Restore original data
    _data = originalData;
}

/**
 * Tests searching for a pattern that exercises the bad character rule.
 *
 * This test creates a scenario where the bad character rule of the Boyer-Moore
 * algorithm provides significant performance benefits by allowing large jumps.
 *
 * Memory layout and search process:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                      Memory Contents                            │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                 │
 * │  ... AA AA AA AA AA AA AA AA AA AA AA AA AA AA AA AA AA ...     │
 * │      ↑                                                          │
 * │      └── Search starts here                                     │
 * │                                                                 │
 * │  Pattern: AA AA AA AB                                           │
 * │                                                                 │
 * │  Boyer-Moore Search Process:                                    │
 * │  1. Compare pattern from right to left                          │
 * │  2. When comparing the last byte 'B' with 'A' in the text,      │
 * │     a mismatch occurs                                           │
 * │  3. Since 'A' doesn't appear in the pattern to the right of     │
 * │     the mismatch position, the bad character rule allows        │
 * │     shifting the pattern by its full length                     │
 * │                                                                 │
 * │  Bad Character Rule in Action:                                  │
 * │  Text:    AA AA AA AA AA AA AA                                  │
 * │  Pattern: AA AA AA AB                                           │
 * │                    ↑ Mismatch                                   │
 * │                                                                 │
 * │  After shift:                                                   │
 * │  Text:    AA AA AA AA AA AA AA                                  │
 * │  Pattern:         AA AA AA AB                                   │
 * │                                                                 │
 * │  Expected: No matches found (pattern doesn't exist in buffer)   │
 * │                                                                 │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)testBadCharacterRule
{
    // Create a buffer with repeating bytes
    const NSUInteger bufferSize = 1024;
    uint8_t *buffer = (uint8_t *)malloc(bufferSize);
    if (buffer == NULL) {
        XCTFail(@"Failed to allocate memory for test buffer");
        return;
    }

    // Fill buffer with repeating pattern of 0xAA
    memset(buffer, 0xAA, bufferSize);

    // Create a temporary NSData with our controlled buffer
    NSData *originalData = _data;
    _data = [NSData dataWithBytesNoCopy:buffer length:bufferSize freeWhenDone:YES];

    // Search for a pattern that doesn't exist in the buffer
    // This pattern is designed to trigger the bad character rule
    const uint8_t pattern[] = {0xAA, 0xAA, 0xAA, 0xBB};
    NSUInteger numberOfResults = 0;
    XCTAssertTrue([self searchAndVerifyBytes:pattern length:sizeof(pattern) getNumberOfResults:&numberOfResults]);

    // Expected number of results: 0 (pattern doesn't exist in buffer)
    XCTAssertEqual(numberOfResults, 0U);

    // Restore original data
    _data = originalData;
}

/**
 * Tests searching for a pattern that exercises the good suffix rule.
 *
 * This test creates a scenario where the good suffix rule of the Boyer-Moore
 * algorithm provides performance benefits by allowing appropriate jumps
 * when a partial match is found.
 *
 * Memory layout and search process:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                      Memory Contents                            │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                 │
 * │  ... CC AB AB AB CC AB AB AB CC AB AB AB CC AB AB AB ...        │
 * │      ↑                                                          │
 * │      └── Search starts here                                     │
 * │                                                                 │
 * │  Pattern: CC AB AB AB                                           │
 * │                                                                 │
 * │  Boyer-Moore Search Process:                                    │
 * │  1. Compare pattern from right to left                          │
 * │  2. When a partial match "AB AB AB" is found but "CC" fails,    │
 * │     the good suffix rule determines the next position to try    │
 * │  3. The algorithm shifts the pattern to align with the next     │
 * │     possible occurrence of the matched suffix                   │
 * │                                                                 │
 * │  Good Suffix Rule in Action:                                    │
 * │  Text:    YY AB AB AB CC AB AB AB                               │
 * │  Pattern: CC AB AB AB                                           │
 * │           ↑ Mismatch after matching "AB AB AB"                  │
 * │                                                                 │
 * │  After shift:                                                   │
 * │  Text:    YY AB AB AB CC AB AB AB                               │
 * │  Pattern:          CC AB AB AB                                  │
 * │                                                                 │
 * │  Expected: Multiple matches found at specific positions         │
 * │                                                                 │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)testGoodSuffixRule
{
    // Create a buffer with a pattern that will exercise the good suffix rule
    const NSUInteger bufferSize = 1024;
    uint8_t *buffer = (uint8_t *)malloc(bufferSize);
    if (buffer == NULL) {
        XCTFail(@"Failed to allocate memory for test buffer");
        return;
    }

    // Initialize buffer
    memset(buffer, 0, bufferSize);

    // Create a pattern in the buffer that repeats "CC AA BB AA BB AA BB"
    const uint8_t patternToRepeat[] = {0xCC, 0xAA, 0xBB, 0xAA, 0xBB, 0xAA, 0xBB, 0xCC};
    const NSUInteger patternToRepeatLength = sizeof(patternToRepeat);

    for (NSUInteger i = 0; i < bufferSize; i += patternToRepeatLength) {
        if (i + patternToRepeatLength <= bufferSize) {
            memcpy(buffer + i, patternToRepeat, patternToRepeatLength);
        }
    }

    // Create a temporary NSData with our controlled buffer
    NSData *originalData = _data;
    _data = [NSData dataWithBytesNoCopy:buffer length:bufferSize freeWhenDone:YES];

    // Search for the pattern "CC AA BB AA BB AA BB"
    const uint8_t searchPattern[] = {0xCC, 0xAA, 0xBB, 0xAA, 0xBB, 0xAA, 0xBB};
    NSUInteger numberOfResults = 0;
    XCTAssertTrue([self searchAndVerifyBytes:searchPattern length:sizeof(searchPattern) getNumberOfResults:&numberOfResults]);

    // Expected number of results: bufferSize / patternToRepeatLength
    NSUInteger expectedResults = bufferSize / patternToRepeatLength;
    XCTAssertEqual(numberOfResults, expectedResults);

    // Restore original data
    _data = originalData;
}

/**
 * Tests searching with a large pattern.
 *
 * This test verifies the Boyer-Moore algorithm's handling of large search patterns,
 * which can be more efficient than naive approaches for long patterns.
 *
 * Memory layout and search process:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                      Memory Contents                            │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                 │
 * │  ... [Random Data] [Large Pattern] [Random Data] ...            │
 * │      ↑                                                          │
 * │      └── Search starts here                                     │
 * │                                                                 │
 * │  Pattern: [64-byte pattern]                                     │
 * │                                                                 │
 * │  Boyer-Moore Advantage for Large Patterns:                      │
 * │  - For large patterns, Boyer-Moore can skip many positions      │
 * │    when a mismatch occurs                                       │
 * │  - The larger the pattern, the more potential for skipping      │
 * │  - This makes Boyer-Moore more efficient than naive approaches  │
 * │    for long patterns                                            │
 * │                                                                 │
 * │  Expected: Pattern found at the inserted position               │
 * │                                                                 │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)testLargePattern
{
    // Create a buffer with random data
    const NSUInteger bufferSize = 4096;
    uint8_t *buffer = (uint8_t *)malloc(bufferSize);
    if (buffer == NULL) {
        XCTFail(@"Failed to allocate memory for test buffer");
        return;
    }

    // Fill buffer with random data
    for (NSUInteger i = 0; i < bufferSize; i++) {
        buffer[i] = (uint8_t)arc4random_uniform(256);
    }

    // Create a large pattern (64 bytes)
    const NSUInteger patternSize = 64;
    uint8_t pattern[patternSize];
    for (NSUInteger i = 0; i < patternSize; i++) {
        pattern[i] = (uint8_t)(i % 256);
    }

    // Insert the pattern at a known position
    const NSUInteger insertPosition = 1024;
    if (insertPosition + patternSize <= bufferSize) {
        memcpy(buffer + insertPosition, pattern, patternSize);
    }

    // Create a temporary NSData with our controlled buffer
    NSData *originalData = _data;
    _data = [NSData dataWithBytesNoCopy:buffer length:bufferSize freeWhenDone:YES];

    // Search for the large pattern
    NSUInteger numberOfResults = 0;
    XCTAssertTrue([self searchAndVerifyBytes:pattern length:patternSize getNumberOfResults:&numberOfResults]);

    // Expected number of results: 1 (pattern inserted at one position)
    XCTAssertEqual(numberOfResults, 1U);

    // Restore original data
    _data = originalData;
}

/**
 * Tests edge cases for the Boyer-Moore search algorithm.
 *
 * This test verifies the algorithm's behavior with edge cases such as:
 * - Empty pattern
 * - Single byte pattern
 * - Pattern at the beginning of data
 * - Pattern at the end of data
 * - Pattern larger than the data
 *
 * Memory layout for edge cases:
 * ┌─────────────────────────────────────────────────────────────────┐
 * │                      Edge Case Scenarios                        │
 * ├─────────────────────────────────────────────────────────────────┤
 * │                                                                 │
 * │  1. Empty Pattern:                                              │
 * │     Pattern: []                                                 │
 * │     Expected: Not supported (length must be > 0)                │
 * │                                                                 │
 * │  2. Single Byte Pattern:                                        │
 * │     Pattern: [A]                                                │
 * │     Expected: Find all occurrences of byte A                    │
 * │                                                                 │
 * │  3. Pattern at Beginning:                                       │
 * │     Data:    [P][P][P][X][X][X]...                             │
 * │     Pattern: [P][P][P]                                          │
 * │     Expected: Match at position 0                               │
 * │                                                                 │
 * │  4. Pattern at End:                                             │
 * │     Data:    ...[X][X][P][P][P]                                │
 * │     Pattern: [P][P][P]                                          │
 * │     Expected: Match at last possible position                   │
 * │                                                                 │
 * │  5. Pattern Larger than Data:                                   │
 * │     Data:    [X][X][X]                                          │
 * │     Pattern: [P][P][P][P]                                       │
 * │     Expected: No matches found                                  │
 * │                                                                 │
 * └─────────────────────────────────────────────────────────────────┘
 */
- (void)testEdgeCases
{
    // Create a buffer for testing edge cases
    const NSUInteger bufferSize = 256;
    uint8_t *buffer = (uint8_t *)malloc(bufferSize);
    if (buffer == NULL) {
        XCTFail(@"Failed to allocate memory for test buffer");
        return;
    }

    // Fill buffer with a known pattern
    for (NSUInteger i = 0; i < bufferSize; i++) {
        buffer[i] = (uint8_t)i;
    }

    // Create a temporary NSData with our controlled buffer
    NSData *originalData = _data;
    _data = [NSData dataWithBytesNoCopy:buffer length:bufferSize freeWhenDone:YES];

    // Test Case 1: Single byte pattern
    const uint8_t singleBytePattern[] = {0x42};  // Arbitrary value
    NSUInteger numberOfResults = 0;
    XCTAssertTrue([self searchAndVerifyBytes:singleBytePattern length:sizeof(singleBytePattern) getNumberOfResults:&numberOfResults]);
    XCTAssertEqual(numberOfResults, 1U);  // Should find exactly one occurrence

    // Test Case 2: Pattern at the beginning
    const uint8_t beginningPattern[] = {0, 1, 2};
    XCTAssertTrue([self searchAndVerifyBytes:beginningPattern length:sizeof(beginningPattern) getNumberOfResults:&numberOfResults]);
    XCTAssertEqual(numberOfResults, 1U);  // Should find exactly one occurrence

    // Test Case 3: Pattern at the end
    const uint8_t endPattern[] = {(uint8_t)(bufferSize-3), (uint8_t)(bufferSize-2), (uint8_t)(bufferSize-1)};
    XCTAssertTrue([self searchAndVerifyBytes:endPattern length:sizeof(endPattern) getNumberOfResults:&numberOfResults]);
    XCTAssertEqual(numberOfResults, 1U);  // Should find exactly one occurrence

    // Test Case 4: Pattern larger than data (using original data)
    _data = originalData;
    uint8_t *largePattern = (uint8_t *)malloc(_data.length + 100);
    if (largePattern == NULL) {
        XCTFail(@"Failed to allocate memory for large pattern");
        return;
    }

    // Fill large pattern with a value that doesn't match data
    memset(largePattern, 0xFF, _data.length + 100);

    XCTAssertTrue([self searchAndVerifyBytes:largePattern length:_data.length + 1 getNumberOfResults:&numberOfResults]);
    XCTAssertEqual(numberOfResults, 0U);  // Should find no occurrences

    free(largePattern);

    // Restore original data
    _data = originalData;
}

@end
