#include "menu_main.h"
#include "config.h"

MenuMain* MenuMain::instance = NULL;

MenuMain* MenuMain::getInstance() {
	if(!instance)
		instance = new MenuMain();
	return instance;
}

void MenuMain::cleanUpInstance() {
	if(instance) {
		delete instance;
		instance = NULL;
	}
}
MenuMain::MenuMain() {
		SDL_Surface *icon = Screen::loadImage("gfx/pacman_desktop.png", 0);
		SDL_SetWindowIcon(Screen::getInstance()->getWindow(), icon);
		SDL_FreeSurface(icon);
		appTitle1 = Screen::getTextSurface(Screen::getHugeFont(), "Pa", Constants::WHITE_COLOR);
		appTitle2 = Screen::getTextSurface(Screen::getHugeFont(), "man", Constants::WHITE_COLOR);
		titlePacman = Screen::loadImage("gfx/title_pacman.png", 0);
		std::string str_version = "version ";
		str_version.append(VERSION);
		version = Screen::getTextSurface(Screen::getSmallFont(), str_version.c_str(), Constants::GRAY_COLOR);
		addMenuItem("Quit");
		addMenuItem("About");
		addMenuItem("Highscore List");
		addMenuItem("Options");
		addMenuItem("Start Game");
		selection = STARTGAME;
		menuoptions = new MenuOptions();
		menuabout = new MenuAbout();
		draw();
}

MenuMain::~MenuMain() {
	SDL_FreeSurface(appTitle1);
	SDL_FreeSurface(appTitle2);
	SDL_FreeSurface(titlePacman);
	SDL_FreeSurface(version);
	delete menuoptions;
	delete menuabout;
}

void MenuMain::drawTitle() {
	SDL_Rect rect;
	rect.x = 0;
	rect.y = 0;
	rect.w = 640;
	rect.h = 480;
	rect.x = (short int) (320 - ((appTitle1->w + titlePacman->w + appTitle2->w) >> 1));
	Screen::getInstance()->draw(appTitle1, rect.x, 30);
	rect.x = (short int) (rect.x + appTitle1->w + titlePacman->w);
	Screen::getInstance()->draw(appTitle2, rect.x, 30);
	rect.x = (short int) (rect.x - titlePacman->w);
	Screen::getInstance()->draw(titlePacman, rect.x, 40);
	Screen::getInstance()->draw(version, (short int)(320 - (version->w >> 1)), 140);
}

int MenuMain::show() {
	GameController::getInstance()->searchAndOpen();
	draw();
	int event;
	while(!(event = eventloop())) {
		SDL_Delay(Constants::MIN_FRAME_DURATION);
		FunnyAnimation::getInstance()->animate();
	}
	FunnyAnimation::cleanUpInstance();
	return (event == 1 ? 1 : 0);
}

int MenuMain::handleSelection() {
	if(selection == STARTGAME)
		return 1;
	else if(selection == OPTIONS) {
		menuoptions->show();
		this->draw();
	}
	else if(selection == HIGHSCORE) {
		HighscoreList::getInstance()->load();
		HighscoreList::getInstance()->show(false, false);
		this->draw();
	}
	else if(selection == ABOUT) {
		menuabout->show();
		this->draw();
	}
	else if(selection == BACK)
		return 2;
	return 0;
}
