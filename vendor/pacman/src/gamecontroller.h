#ifndef GAMECONTROLLER
#define GAMECONTROLLER

#include <SDL2/SDL.h>
#include <SDL2/SDL_gamecontroller.h>
#include <iostream>
#include "platform.h"
class GameController {
	public:
		static GameController *getInstance();
		static void cleanUpInstance();

		void searchAndOpen(bool reopen = false);
		bool isPresent();

	private:
		static GameController *instance;
        // constructor and destructor
		GameController();
		~GameController();

		SDL_GameController *gameController;
};

#endif
