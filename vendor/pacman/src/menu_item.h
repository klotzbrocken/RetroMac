#ifndef MENU_ITEM_H
#define MENU_ITEM_H
#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include "platform.h"
#include "constants.h"
#include "screen.h"

class MenuItem {
	public:
		MenuItem(const char* menuItem, const char* menuItemAlt = NULL);
		~MenuItem();
		SDL_Surface* getCurrentMenuItem();
		void setSelectMenuItem(bool set = false);
		void toggleMenuItem();
		void setMenuItemAlt(bool set = false);
		void setXPosition(int x);
		void setYPosition(int y);
		int getXPosition() const;
		int getYPosition() const;
	private:
		int x, y;
		bool selected, altMenu;
		SDL_Surface *menuItem, *menuItemSel; 
		SDL_Surface *menuItemAlt, *menuItemSelAlt;
};
#endif
