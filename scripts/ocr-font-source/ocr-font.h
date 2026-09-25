
#pragma once

#include <vector>

struct UShortPoint {
	unsigned short x;
	unsigned short y;
};

struct OcrChar {
	char character;
	const std::vector<UShortPoint> outlinePoints;
};

struct OcrAlphabet {
	// A description of each character
	std::vector<OcrChar> characters;

	// [ocrCharHeightInPixels][ocrCharWidthInPixels][characters.size()]
	// entry = [y][x][characterIndex]
	//   penalty = observedBitWasWhite ? (entry >> 4) : (entry & 0xf)
	const unsigned char* penalties;
};

struct OcrFont {
	const float charWidthOverFontSize;
	const float charHeightOverFontSize;
	const float fontBaselineFraction;
	const int ocrCharWidthInPixels;
	const int ocrCharHeightInPixels;
	const int outlineCharWidthInPixels;
	const int outlineCharHeightInPixels;
	const OcrAlphabet letters;
	const OcrAlphabet digits;
};
