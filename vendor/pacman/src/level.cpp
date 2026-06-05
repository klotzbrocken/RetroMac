#include "level.h"
#include <iostream>

Level *Level::instance = NULL;

Level *Level::getInstance() {
	if(!instance)
		instance = new Level();
	return instance;
}

void Level::cleanUpInstance() {
	if(instance) {
		delete instance;
		instance = NULL;
	}
}

Level::Level():
	level(1)
{
}

Level::~Level() {
}

int Level::getLevelNumber() {
	return level;
}

void Level::setLevel(int const level) {
	this->level = level;
}

void Level::nextLevel() {
	++level;
}

int Level::getPillLimit() {
	switch(level) {
		case 1:
			return -1;
		case 2:
		case 3:
			return 5;
		case 4:
		case 5:
			return 10;
		default:
			return 15;
	}
}

int Level::getHuntingModeTime() {
	switch(level) {
		case 1:
		case 2:
			return 7000;
		case 3:
		case 4:
			return 6000;
		case 5:
			return 5000;
		default:
			return 4000;
	}
}

int Level::getFruitDisplayTime() {
	switch(level) {
		case 1:
			return 10000;
		case 2:
			return 9000;
		case 3:
		case 4:
			return 8000;
		case 5:
		case 6:
			return 7000;
		case 7:
		case 8:
			return 6000;
		default:
			return 5000;
	}
}
