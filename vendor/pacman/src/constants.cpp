#include "constants.h"

SDL_Color Constants::WHITE_COLOR  = {255, 255, 255,   0};
SDL_Color Constants::YELLOW_COLOR = {255, 247,  11,   0};
SDL_Color Constants::RED_COLOR    = {255,   0,   0,   0};
SDL_Color Constants::GRAY_COLOR   = {191, 191, 191,   0};

SDL_Color Constants::BLINKY_COLOR = {255,   0,   0,   0};
SDL_Color Constants::PINKY_COLOR  = {247,  94, 177,   0};
SDL_Color Constants::INKY_COLOR   = { 34, 245, 233,   0};
SDL_Color Constants::CLYDE_COLOR  = {242, 177,  37,   0};

Constants::Constants() {
}

Constants::~Constants() {
}

SDL_Color Constants::getIndexedColor(int color) {
	switch (color) {
		case YELLOW:
			return YELLOW_COLOR;
		case RED:
			return RED_COLOR;
		case GRAY:
			return GRAY_COLOR;
		default:
			return WHITE_COLOR;
	}
}
