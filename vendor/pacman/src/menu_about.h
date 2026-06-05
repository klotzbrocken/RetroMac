#ifndef MENU_ABOUT_H
#define MENU_ABOUT_H
#include "menu.h"

class MenuAbout : public Menu {
	public:
		MenuAbout();
		~MenuAbout();
		void draw(bool updateAll = true);
	private:
		enum Entries {BACK};
		int handleSelection();
		SDL_Surface *idea, *coding, *coding2;
};
#endif