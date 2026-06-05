#ifndef LABYRINTH_H
#define LABYRINTH_H

#include <SDL2/SDL_ttf.h>
#include <vector>
#include "constants.h"
#include "screen.h"
#include "pille.h"
#include "rail.h"
#include "sounds.h"
#include "platform.h"
#include "ghost_figur.h"
#include "pacman_figur.h"
#include "labyrinth_observer.h"
using namespace std;

class Level;

class Labyrinth {
	public:
		static Labyrinth* getInstance();
		static void cleanUpInstance();

		// At the left and right of the tunnel, there are two black rectangles,
		// below which pacman and the ghosts will disappear if they leave the
		// level to the left or right.
		void draw_blocks();

		/* draw pills, but only if Blinky has moved */
		void draw_pillen();

		// superpill animation
		void pill_animation();

		void drawScoreValue();
		void drawLevelNumber();

		Pille pillen[Constants::NUMBER_PILLS];  // TODO: hide (currently used within Pacman::check_eat_pills)
		Rail *array_rails[Constants::NUMBER_RAILS];  // TODO: hide (currently used within Pacman::move and Pacman::check_eat_pills)

		// increases the bonus stage to the next value: 200 -> 400 -> 800 -> 1600
		void increaseBonusStage();  // TODO: move to new class Player
		void resetBonusStage();  // reset to 200  // TODO: move to Player

		// adds a value to the player's score
		// TODO: move both addScore methods to Player, create new method setSmallScore(value,x,y) here
		void addScore(int value, int show_x, int show_y);  // use this method if the score should be displayed
		void addScore(int value);                          // use this method if the score should not be displayed
		void drawSmallScore();
		void hideSmallScore();
		// adds the current bonus stage to the player's score
		void addBonusScore(int show_x, int show_y);  // TODO: move to Player
		// retrieve current score
		int getScore();  // TODO: move to Player
		int getLevelNumber();

		// remove the pill from the level (after it was eaten)
		void removePill(int idxPill);

		// get number of remaining pills
		int getNumRemainingPills() const;

		// set init text, color is 1=yellow, 2=red, white otherwise.
		void setInitText(const char *text, int color = Constants::WHITE);

		// level init text
		void drawInitText();

		// hide init text
		void hideInitText();

		// (re-)init level
		void resetAllFigures();
		void nextLevel();
		void resetLevel(int level = 0);

		// Check whether enough pills have been eaten to display the next fruit.
		// If the fruit is displayed, decrement it's display time, and hide it
		// if 10 s are over.
		void checkFruit(int ms);
		// hide the fruit (when it's display time is over, or it has been eaten)
		void hideFruit();
		// fruit is displayed
		int fruitIsDisplayed();
		// get fruit bonus
		int getFruitBonus() const;
		// draws the fruit, if it is displayed
		void drawFruit();
		// draw fruits in info area
		void drawInfoFruits();

		// deprecated (use Sounds::getInstance() instead)
		Sounds* getSounds();  // TODO: eliminate after eliminating all references

		// Return indexes of the Rails from the specified point (x,y), -1 if there is no such rail.
		void getRailsForPoint(int x, int y, int *left, int *right, int *up, int *down);

		void resetScore();  // TODO: move to Player

		// Return the current surface of the superpill according to their animation step.
		SDL_Surface *get_superpill_sf();

		void setLabyrinthObserver(LabyrinthObserver* labyrinthObserver);

	private:
		static Labyrinth *instance;

		//constructor and destructor
		Labyrinth();
		~Labyrinth();

		LabyrinthObserver* labyrinthObserver[4];
		int cnt_pill_animation;
		Rail *s0,  *s1,  *s2,  *s3,  *s4,  *s5,  *s6,  *s7,  *s8,  *s9,
		    *s10, *s11, *s12, *s13, *s14, *s15, *s16, *s17, *s18, *s19,
		    *s20, *s21, *s22, *s23, *s24, *s25,	*s26, *s27, *s28, *s29,
		    *s30, *s31, *s32, *s33, *s34, *s35, *s36, *s37, *s38, *s39,
		    *s40, *s41, *s42, *s43, *s44, *s45, *s46, *s47, *s48, *s49,
		    *s50, *s51, *s52, *s53, *s54, *s55, *s56, *s57, *s58, *s59,
		    *s60, *s61, *s62, *s63, *s64, *s65, *s66, *s67, *s68, *s69,
		    *s70, *s71, *s72, *s73, *s74, *s75, *s76, *s77, *s78, *s79,
		    *s80, *s81, *s82, *s83, *s84, *s85, *s86, *s87, *s88, *s89,
		    *s90;  // TODO: really necessary? Try to eliminate it, and use the arrays only.

		SDL_Surface *pille, *superpille, *ar_superpille[5];
		int punktestand, lastPunktestand;
		int bonus_stage;  // 200, 400, 800, 1600 (increases for each eaten ghost)
		SDL_Surface *smallScore, *initText, *score, *infoFruit, *fruit, *pillSurface, *bgSurface, *levelNumber;
		int smallScore_x, smallScore_y;
		int cnt_pills;
		//int level;
		Level *level;
		int next_fruit;
		int fruit_display_time;
		int cnt_displayed_fruits;
		int fruit_displayed;
		int fruit_bonus;
		int idxSuperpills[4];
		// initially, throw some pills across the level
		void init_pillen(bool firstInit);
		int number_rails() const;

		Rail *array_rails_pills[Constants::NUMBER_RAILS_PILLS];  // TODO: could by removed if the Rails know about whether they have pills or not.

		// load the fruit that belongs to the current level
		void loadLevelFruit();
		// start the fruit randomizer
		// first fruit after 50, 60, 70 or 80
		// eaten pills
		void startFruitRandomizer(int new_level);
		// set fruit bonus
		void setFruitBonus(int fruit_bonus);

		// Return the background image, will be loaded if not yet done
		SDL_Surface *getBackground();
		vector<LabyrinthObserver*> vec_observer;
};
#endif
