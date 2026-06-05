#include "menu_item.h"

MenuItem::MenuItem(const char* menuItem, const char* menuItemAlt):
	selected(false),
	altMenu(false),
	menuItem(NULL),
	menuItemSel(NULL),
	menuItemAlt(NULL),
	menuItemSelAlt(NULL) {
	this->menuItem = Screen::getTextSurface(Screen::getFont(), menuItem, Constants::GRAY_COLOR);
	this->menuItemSel = Screen::getTextSurface(Screen::getLargeFont(), menuItem, Constants::WHITE_COLOR);
	if(menuItemAlt) {
		this->menuItemAlt = Screen::getTextSurface(Screen::getFont(), menuItemAlt, Constants::GRAY_COLOR);
		this->menuItemSelAlt = Screen::getTextSurface(Screen::getLargeFont(), menuItemAlt, Constants::WHITE_COLOR);
	}
}

MenuItem::~MenuItem() {
	SDL_FreeSurface(menuItem);
	SDL_FreeSurface(menuItemSel);
	SDL_FreeSurface(menuItemAlt);
	SDL_FreeSurface(menuItemSelAlt);
}

SDL_Surface* MenuItem::getCurrentMenuItem() {
	if(selected)
		return (altMenu ? menuItemSelAlt : menuItemSel);
	else
		return (altMenu ? menuItemAlt : menuItem);
}

void MenuItem::setSelectMenuItem(bool set) {
	selected = set;
}

void MenuItem::toggleMenuItem() {
	if(menuItemAlt)
		altMenu = altMenu ? false : true;
}

void MenuItem::setMenuItemAlt(bool set) {
	altMenu = set;
}

void MenuItem::setXPosition(int x) {
	this->x = x;
}

void MenuItem::setYPosition(int y) {
	this->y = y;
}

int MenuItem::getXPosition() const {
	return this->x;
}

int MenuItem::getYPosition() const {
	return this->y;
}
