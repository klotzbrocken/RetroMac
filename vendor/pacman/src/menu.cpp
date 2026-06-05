#include "menu.h"

Menu::Menu(const char* title):
	selection(0) {
	menuTitle = title ? Screen::getTextSurface(Screen::getVeryLargeFont(), title, Constants::WHITE_COLOR) : NULL;
}
Menu::~Menu() {
	SDL_FreeSurface(menuTitle);
	for(unsigned int i = 0; i < menuItems.size(); ++i)
		delete menuItems.at(i);
}

void Menu::draw(bool updateAll) {
	if (updateAll) {
		Screen::getInstance()->clear();
		drawTitle();
		drawMenuItems();
		Screen::getInstance()->addUpdateClipRect();
	} else {
		drawMenuItems();
	}
	Screen::getInstance()->Refresh();
}

void Menu::drawMenuItems() {
	const int vertical_pad = 35;
	SDL_Rect rect;
	rect.x = 0;
	rect.w = Constants::WINDOW_WIDTH;
	rect.y = 430 - (int)menuItems.size()*vertical_pad;
	rect.h = Constants::WINDOW_HEIGHT - rect.y;
	Screen::getInstance()->fillRect(&rect, 0, 0, 0);
	for(uint8_t i = 0; i < menuItems.size(); ++i) {
		menuItems.at(i)->setSelectMenuItem(selection == i);
		Screen::getInstance()->draw(menuItems.at(i)->getCurrentMenuItem(), 320 - (menuItems.at(i)->getCurrentMenuItem()->w >> 1), (430 - (i)*vertical_pad) - (menuItems.at(i)->getCurrentMenuItem()->h >> 1));
	}
	Screen::getInstance()->AddUpdateRects(rect.x, rect.y, rect.w, rect.h);
}

int Menu::show() {
	draw();
	int event;
	while(!(event = eventloop()))
		SDL_Delay(Constants::MIN_FRAME_DURATION);
	return event;
}

void Menu::drawTitle() {
	if(menuTitle)
		Screen::getInstance()->draw_dynamic_content(menuTitle, 320 - (menuTitle->w >> 1), 50);
}

void Menu::addMenuItem(const char* menuItem, const char* menuItemAlt) {
	menuItems.push_back(new MenuItem(menuItem, menuItemAlt));
	menuItems.back()->setXPosition(320 - (menuItems.back()->getCurrentMenuItem()->w >> 1));
	menuItems.back()->setYPosition(430 - (((int)menuItems.size()-1)*35) - (menuItems.back()->getCurrentMenuItem()->h >> 1));
}

int Menu::eventloop() {
	SDL_Event event;
	int event_x, event_y;
	while(SDL_PollEvent(&event)) {
		switch(event.type) {
		case SDL_KEYDOWN:
			if(event.key.keysym.sym == SDLK_RETURN)
				return handleSelection();
			else if(event.key.keysym.sym == SDLK_UP || event.key.keysym.sym == SDLK_k)
				menuItemUp();
			else if(event.key.keysym.sym == SDLK_DOWN || event.key.keysym.sym == SDLK_j)
				menuItemDown();
			else if(event.key.keysym.sym == SDLK_f) {
				Screen::getInstance()->toggleFullscreen();
				updateMenuItemNames();
				this->draw();
			}
			else if(event.key.keysym.sym == SDLK_s) {
				Sounds::getInstance()->toggleEnabled();
				updateMenuItemNames();
				this->draw();
			}
			else if(event.key.keysym.sym == SDLK_m) {
				Sounds::getInstance()->toggleMusicEnabled();
				updateMenuItemNames();
				this->draw();
			}
			else if((event.key.keysym.sym == SDLK_q)||(event.key.keysym.sym == SDLK_ESCAPE))
				return 2;
			break;
		case SDL_CONTROLLERBUTTONDOWN:
			if (event.cbutton.button == SDL_CONTROLLER_BUTTON_DPAD_UP)
				menuItemUp();
			else if(event.cbutton.button == SDL_CONTROLLER_BUTTON_DPAD_DOWN)
				menuItemDown();
			else if(event.cbutton.button == SDL_CONTROLLER_BUTTON_DPAD_RIGHT || event.cbutton.button == SDL_CONTROLLER_BUTTON_START)
				return handleSelection();
			else if(event.cbutton.button == SDL_CONTROLLER_BUTTON_BACK)
				return 2;
			break;
		case SDL_CONTROLLERAXISMOTION:
			if((event.caxis.axis == SDL_CONTROLLER_AXIS_LEFTY) && (event.caxis.value < -Constants::AXIS_ACTIVE_ZONE))
				menuItemUp();
			else if((event.caxis.axis == SDL_CONTROLLER_AXIS_LEFTY) && (event.caxis.value > Constants::AXIS_ACTIVE_ZONE))
				menuItemDown();
			else if((event.caxis.axis == SDL_CONTROLLER_AXIS_LEFTX) && (event.caxis.value > Constants::AXIS_ACTIVE_ZONE))
				return handleSelection();
			else if((event.caxis.axis == SDL_CONTROLLER_AXIS_LEFTX) && (event.caxis.value < -Constants::AXIS_ACTIVE_ZONE))
				return 2;
			break;
		case SDL_MOUSEMOTION:
			event_x = Screen::xToClipRect(event.motion.x);
			event_y = Screen::yToClipRect(event.motion.y);
			for(uint8_t i = 0; i < menuItems.size(); ++i) {
				if (menuItems.at(i)->getXPosition() <= event_x &&
					event_x <= menuItems.at(i)->getXPosition()+menuItems.at(i)->getCurrentMenuItem()->w &&
					menuItems.at(i)->getYPosition() <= event_y &&
					event_y <= menuItems.at(i)->getYPosition()+menuItems.at(i)->getCurrentMenuItem()->h)
				{
					menuItemSelect(i);
					break;
				}
			}
			break;
		case SDL_MOUSEBUTTONDOWN:
			event_x = Screen::xToClipRect(event.motion.x);
			event_y = Screen::yToClipRect(event.motion.y);
			if (event.button.button == SDL_BUTTON_LEFT) {
				if (menuItems.at(selection)->getXPosition() <= event_x &&
					event_x <= menuItems.at(selection)->getXPosition()+menuItems.at(selection)->getCurrentMenuItem()->w &&
					menuItems.at(selection)->getYPosition() <= event_y &&
					event_y <= menuItems.at(selection)->getYPosition()+menuItems.at(selection)->getCurrentMenuItem()->h)
				{
					return handleSelection();
				}
			}
			break;
		case SDL_QUIT:
				return 2;
		}
		// Redraw, when overlapped by foreign window
		if(event.window.event == SDL_WINDOWEVENT_EXPOSED ||
		   event.window.event == SDL_WINDOWEVENT_FOCUS_GAINED) {
			Screen::getInstance()->clearOutsideClipRect();
			Screen::getInstance()->addTotalUpdateRect();
			Screen::getInstance()->Refresh();
		}
	}
	return 0;
}

void Menu::menuItemDown() {
	selection = (uint8_t) (selection - 1 + (uint8_t)menuItems.size()) % (uint8_t)menuItems.size();
	draw(false);
}

void Menu::menuItemUp() {
	selection = (uint8_t) (selection + 1) % (uint8_t)menuItems.size();
	draw(false);
}

void Menu::menuItemSelect(uint8_t selection) {
	if (this->selection != selection) {
		this->selection = selection;
		draw(false);
	}
}

MenuItem* Menu::getSelectedMenuItem() {
	return menuItems.at(selection);
}

int Menu::handleSelection() {
	return 0;
}

void Menu::updateMenuItemNames() {}
