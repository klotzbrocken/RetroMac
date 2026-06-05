#ifndef MENU_MAIN_H
#define MENU_MAIN_H
#include "pacman_figur.h"
#include "ghost_figur.h"
#include "menu_options.h"
#include "menu_about.h"
#include "funny_animation.h"
#include "highscore.h"
#include "gamecontroller.h"

class MenuMain : public Menu {
	public:
		static MenuMain* getInstance();
		static void cleanUpInstance();
		int show();
	private:
		MenuMain();
		~MenuMain();
		static MenuMain* instance;
		enum Entries {BACK, ABOUT, HIGHSCORE, OPTIONS, STARTGAME};
		Menu *menuoptions;
		Menu *menuabout;
		SDL_Surface *appTitle1, *appTitle2, *titlePacman, *version;
		int handleSelection();
		void drawTitle();
};
#endif
