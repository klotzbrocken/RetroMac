#ifndef CONSTANTS_H
#define CONSTANTS_H

#include <SDL2/SDL.h>

class Constants {
	public:
		static const uint16_t INTELLIGENCE_BLINKY     = 90;    // intelligence for each ghost
		static const uint16_t INTELLIGENCE_PINKY      = 60;
		static const uint16_t INTELLIGENCE_INKY       = 30;
		static const uint16_t INTELLIGENCE_CLYDE      = 0;
		static const uint16_t INIT_UP_DOWN_BLINKY     = 0;     // initial up/down cycles before the ghost will be allowed to leave the castle
		static const uint16_t INIT_UP_DOWN_PINKY      = 0;
		static const uint16_t INIT_UP_DOWN_INKY       = 5;
		static const uint16_t INIT_UP_DOWN_CLYDE      = 11;
		static const int MIN_FRAME_DURATION           = 30;    // duration of a loop in milliseconds (i.e. minimum time between frames)
		static const uint16_t START_OFFSET            = 4500;  // waiting time when the level starts, in ms
		static const uint16_t START_OFFSET_2          = 1500;  // waiting time after respawn, in ms
		static const uint16_t WAIT_FOR_NEW_LEVEL      = 1000;  // waiting time between eating last pill and display of the new level
		static const uint16_t PAUSE_AFTER_BONUS_SCORE = 400;   // waiting time after eating a ghost or a fruit
		static const int WHITE                        = 0;     // colors for init text
		static const int YELLOW                       = 1;
		static const int RED                          = 2;
		static const int GRAY                         = 3;
		static const int INITIAL_LIVES                = 3;     // number of times the player must die to get the "game over"
		static const int PACMAN_INITIAL_X             = 310;   // starting position of Pacman
		static const int PACMAN_INITIAL_Y             = 339;
		static const int PACMAN_V_FAST                = 120;   // pacman's speed when not eating
		static const int PACMAN_V_SLOW                = 100;    // pacman's speed while eating
		static const uint16_t PACMAN_WECHSEL_RATE     = 7;     // load a new image for pacman after a movement of this number of pixels
		static const int BLINKY_INITIAL_X             = 310;   // starting positions of the ghosts
		static const int BLINKY_INITIAL_Y             = 174;
		static const int PINKY_INITIAL_X              = 310;
		static const int PINKY_INITIAL_Y              = 222;
		static const int INKY_INITIAL_X               = 280;
		static const int INKY_INITIAL_Y               = 222;
		static const int CLYDE_INITIAL_X              = 340;
		static const int CLYDE_INITIAL_Y              = 222;
		static const int TOTAL_NUM_GHOSTS             = 4;     // total number of ghosts in the game
		static const int GHOSTS_V_FAST                = 120;    // fast speed of the ghosts
		static const int GHOSTS_V_NORMAL              = 100;    // normal speed of the ghosts
		static const int GHOSTS_V_SLOW                = 60;    // speed at hunting mode
		static const int NUMBER_RAILS                 = 91;    // number of rails
		static const int NUMBER_RAILS_PILLS           = 69;    // number of pill-filled rails
		static const int NUMBER_PILLS                 = 246;   // number of pills
		static const int NORMAL_PILL_SCORE            = 10;    // score that will be added if Pacman eats a normal pill
		static const int SUPER_PILL_SCORE             = 50;    // score that will be added if Pacman eats a superpill
		static const int LEFT_TUNNEL_BLOCK_X          = 100;   // position of tunnel blocks
		static const int RIGHT_TUNNEL_BLOCK_X         = 515;
		static const int TUNNEL_BLOCK_Y               = 215;
		static const int TUNNEL_BLOCK_WIDTH           = 30;
		static const int TUNNEL_BLOCK_HEIGHT          = 30;
		static const int CASTLE_X                     = 310;   // target point within castle (for returning ghosts)
		static const int CASTLE_Y                     = 190;
		static const int INIT_TEXT_X                  = 320;   // center position of init text
		static const int INIT_TEXT_Y                  = 268;
		static const int FRUIT_X                      = 310;   // position (upper left corner) of the fruit that can be eaten
		static const int FRUIT_Y                      = 257;
		static const int INFO_FRUITS_X                = 525;   // position (upper left corner) of the level's info fruit
		static const int INFO_FRUITS_Y                = 430;
		static const int INFO_FRUITS_DISTANCE         = 3;     // distance between fruit pictures
		static const int LIVES_X                      = 530;   // position (upper left corner) of the lives display
		static const int LIVES_Y                      = 110;
		static const int LIVES_DISTANCE               = 3;     // distance between lives pictures
		static const int SCORE_X                      = 530;   // position (upper left corner) of the score display
		static const int SCORE_Y                      = 30;
		static const int SCORE_VALUE_Y                = 60;
		static const int LEVEL_X                      = 530;   // position (upper left corner) of the level display
		static const int LEVEL_Y                      = 160;
		static const int LEVEL_NUMBER_Y               = 190;
		static const int WINDOW_WIDTH                 = 640;   // screen settings
		static const int WINDOW_HEIGHT                = 480;
		static const int BITS_PER_PIXEL               = 24;
		static const int MAX_UPDATE_RECTS             = 200;
		static const uint8_t HIGHSCORE_LIST_MAX_SIZE  = 10;    // maximum number of entries in highscore list
		static const int HIGHSCORE_COLUMN_SPACING     = 20;    // space between the columns of the highscore table
		static const uint16_t AXIS_ACTIVE_ZONE		  = 8000;  // axis value to interpret as action
#ifdef _WIN32
		static const char FILE_SEPARATOR              = '\\';
#else
		static const char FILE_SEPARATOR              = '/';
#endif

		static SDL_Color WHITE_COLOR;
		static SDL_Color YELLOW_COLOR;
		static SDL_Color RED_COLOR;
		static SDL_Color GRAY_COLOR;
		static SDL_Color BLINKY_COLOR;
		static SDL_Color PINKY_COLOR;
		static SDL_Color INKY_COLOR;
		static SDL_Color CLYDE_COLOR;

		static SDL_Color getIndexedColor(int color);

	private:
		Constants();
		~Constants();
};

#endif
