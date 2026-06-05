#ifndef LEVEL_H
#define LEVEL_H

class Level {
	public:
		static Level *getInstance();
		static void cleanUpInstance();
		int getLevelNumber();
		void setLevel(int const level);
		void nextLevel();
		int getPillLimit();
		int getHuntingModeTime();
		int getFruitDisplayTime();
	private:
		static Level *instance;

		// constructor and destructor
		Level();
		~Level();

		int level;
};
#endif
