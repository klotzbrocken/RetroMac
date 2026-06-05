#ifndef HIGHSCORE_H
#define HIGHSCORE_H

#include "constants.h"
#include <string>
#include <vector>
#include <iostream>
#include <fstream>
#include <SDL2/SDL.h>
#include <SDL2/SDL_gamecontroller.h>
#include "screen.h"
#include "sounds.h"
#include "platform.h"
#include <stdlib.h>

class HighscoreEntry {
	public:
		HighscoreEntry(std::string playerName, int score, int level);
		~HighscoreEntry();
		int getScore() { return score; }
		int getLevel() { return level; }
		const char *getPlayerName() { return playerName.c_str(); }
		int getPlayerNameLength() { return (int)playerName.length(); }
		void addCharToPlayerName(const char c);
		void removeLastCharFromPlayerName();
		void rotateLastCharOfPlayerName(bool reverse);
		void setPlayerName(const char *newName) { playerName = newName; }
	private:
		std::string playerName;
		int score;
		int level;
};

class HighscoreList {
	public:
		static HighscoreList *getInstance();
		static void cleanUpInstance();
		int insertEntry(HighscoreEntry *entry);  // returns index of the inserted entry (i.e. its position-1), or -1 if it was not inserted (e.g. because the score was not enough)
		int getIdxLastInsertedEntry() { return idxLastInsertedEntry; }
		void print();
		void show(bool nameAlterable, bool highlightLast);
		void resetHighlightedEntry();
		void load();
		void save();
		HighscoreEntry *getEntry(int index);
		bool isReadonly() { return readonly; }
	private:
		static HighscoreList *instance;
		HighscoreList(uint8_t maxSize);
		~HighscoreList();
		void draw(bool nameAlterable, bool highlightLast);
		void finishEntry();
		bool eventloop(bool nameAlterable, bool *redrawNeeded);
		bool readEncryptedLine(std::ifstream &f, std::string &line);
		bool readLine(std::ifstream &f, std::string &line);
		uint8_t maxSize;
		std::vector<HighscoreEntry*> *entries;
		int idxLastInsertedEntry, idxHighlightedEntry;
		SDL_Surface *sfTitle, *sfPosTitle, *sfNameTitle, *sfScoreTitle, *sfLevelTitle,
		            *sfBackItem, *sfCaret, *sfCurrentPos, *sfCurrentName, *sfCurrentScore,
		            *sfCurrentLevel, *sfReadonly;
		SDL_Surface **sfPositions, **sfPlayerNames, **sfScores, **sfLevels;
		std::string filePath, encryptionKey, rawEncryptionKey;
		bool fileIsEncrypted, readonly;
		int nextKeyPosition;
};

#endif
