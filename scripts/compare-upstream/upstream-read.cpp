// Reads grayscale frames (binary PGM), whose paths come one per line on stdin, with upstream
// read-dicekey's DiceKeyImageProcessor::processImage, and prints one line per frame:
//   path, milliseconds, isFinished() as 0 or 1, the 25 faces of diceKeyRead() as 75 characters
//   (letter, digit, clockwise turns 0-3; "---" where the face is not isDefined()), and each
//   face's errorSize() ("-" where not defined), comma separated.
// Without --merge every frame gets a fresh processor: one frame, nothing carried over. With --merge
// one processor reads the frames in order, merging as upstream's camera loop does.

#include <chrono>
#include <fstream>
#include <iostream>
#include <memory>
#include <string>
#include <vector>

#include "read-dicekey.hpp"

static bool readPGM(const std::string &path, int &width, int &height, std::vector<unsigned char> &pixels) {
	std::ifstream in(path, std::ios::binary);
	std::string magic;
	int maxValue;
	in >> magic >> width >> height >> maxValue;
	in.get();
	if (!in || magic != "P5" || maxValue != 255) return false;
	pixels.resize(size_t(width) * size_t(height));
	in.read(reinterpret_cast<char *>(pixels.data()), pixels.size());
	return bool(in);
}

int main(int argc, char **argv) {
	const bool merge = argc > 1 && std::string(argv[1]) == "--merge";
	std::unique_ptr<DiceKeyImageProcessor> processor;
	std::string path;
	while (std::getline(std::cin, path)) {
		int width, height;
		std::vector<unsigned char> pixels;
		if (!readPGM(path, width, height, pixels)) {
			std::cerr << "cannot read " << path << "\n";
			return 1;
		}
		if (!merge || !processor) processor.reset(new DiceKeyImageProcessor());
		try {
			const auto start = std::chrono::steady_clock::now();
			processor->processImage(width, height, size_t(width), pixels.data());
			const double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - start).count();
			const DiceKey<FaceRead> key = processor->diceKeyRead();
			std::string faces, errors;
			for (int f = 0; f < NumberOfFaces; f++) {
				if (key.isInitialized() && key.faces[f].isDefined()) {
					const FaceRead &face = key.faces[f];
					faces += std::string(1, face.letter()) + face.digit() + char('0' + face.orientationAs0to3ClockwiseTurnsFromUpright());
					errors += std::to_string(face.errorSize());
				} else {
					faces += "---";
					errors += "-";
				}
				if (f < NumberOfFaces - 1) errors += ",";
			}
			std::cout << path << "\t" << ms << "\t" << processor->isFinished() << "\t" << faces << "\t" << errors << "\n";
		} catch (...) {
			std::cout << path << "\texception\n";
		}
	}
	return 0;
}
