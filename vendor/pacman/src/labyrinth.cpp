#include "labyrinth.h"
#include "game.h"
#include <sstream>
#include "level.h"

Labyrinth *Labyrinth::instance = NULL;

Labyrinth *Labyrinth::getInstance() {
	if (!instance) {
		instance = new Labyrinth();
	}
	return instance;
}

void Labyrinth::cleanUpInstance() {
	if (instance) {
		delete instance;
		instance = NULL;
	}
}

Labyrinth::Labyrinth():
	cnt_pill_animation(0),
	punktestand(0),
	lastPunktestand(0),
	bonus_stage(200),
	smallScore(NULL),
	score(NULL),
	initText(NULL),
	infoFruit(NULL),
	fruit(NULL),
	pillSurface(NULL),
	bgSurface(NULL),
	levelNumber(NULL),
	cnt_pills(0){
	// horizontal rails, row by row, from left to right
	s0  = new Rail(138,  37, 207,  37);
	s1  = new Rail(207,  37, 290,  37);

	s2  = new Rail(330,  37, 412,  37);
	s3  = new Rail(412,  37, 480,  37);

	s4  = new Rail(138,  92, 207,  92);
	s5  = new Rail(207,  92, 249,  92);
	s6  = new Rail(249,  92, 290,  92);
	s7  = new Rail(290,  92, 330,  92);
	s8  = new Rail(330,  92, 371,  92);
	s9  = new Rail(371,  92, 412,  92);
	s10 = new Rail(412,  92, 480,  92);

	s11 = new Rail(138, 133, 207, 133);

	s12 = new Rail(249, 133, 290, 133);

	s13 = new Rail(330, 133, 371, 133);

	s14 = new Rail(412, 133, 480, 133);

	s15 = new Rail(249, 174, 290, 174);
	s16 = new Rail(290, 174, 310, 174);
	s17 = new Rail(310, 174, 330, 174);
	s18 = new Rail(330, 174, 371, 174);

	s19 = new Rail(100, 215, 207, 215);  // tunnel left
	s20 = new Rail(207, 215, 249, 215);

	s21 = new Rail(371, 215, 412, 215);
	s22 = new Rail(412, 215, 515, 215);  // tunnel right

	s23 = new Rail(249, 257, 371, 257);

	s24 = new Rail(138, 298, 207, 298);
	s25 = new Rail(207, 298, 249, 298);
	s26 = new Rail(249, 298, 290, 298);

	s27 = new Rail(330, 298, 371, 298);
	s28 = new Rail(371, 298, 412, 298);
	s29 = new Rail(412, 298, 480, 298);

	s30 = new Rail(138, 339, 166, 339);

	s31 = new Rail(207, 339, 249, 339);
	s32 = new Rail(249, 339, 290, 339);
	s33 = new Rail(290, 339, 330, 339);
	s34 = new Rail(330, 339, 371, 339);
	s35 = new Rail(371, 339, 412, 339);

	s36 = new Rail(452, 339, 480, 339);

	s37 = new Rail(138, 380, 166, 380);
	s38 = new Rail(166, 380, 207, 380);

	s39 = new Rail(249, 380, 290, 380);

	s40 = new Rail(330, 380, 371, 380);

	s41 = new Rail(412, 380, 452, 380);
	s42 = new Rail(452, 380, 480, 380);

	s43 = new Rail(138, 421, 290, 421);
	s44 = new Rail(290, 421, 330, 421);
	s45 = new Rail(330, 421, 480, 421);

	// vertical rails, column by column, from top to bottom
	s46 = new Rail(138,  37, 138,  92);
	s47 = new Rail(138,  92, 138, 133);

	s48 = new Rail(138, 298, 138, 339);

	s49 = new Rail(138, 380, 138, 421);

	s50 = new Rail(166, 339, 166, 380);

	s51 = new Rail(207,  37, 207,  92);
	s52 = new Rail(207,  92, 207, 133);
	s53 = new Rail(207, 133, 207, 215);
	s54 = new Rail(207, 215, 207, 298);
	s55 = new Rail(207, 298, 207, 339);
	s56 = new Rail(207, 339, 207, 380);

	s57 = new Rail(249,  92, 249, 133);

	s58 = new Rail(249, 174, 249, 215);
	s59 = new Rail(249, 215, 249, 257);
	s60 = new Rail(249, 257, 249, 298);

	s61 = new Rail(249, 339, 249, 380);

	s62 = new Rail(290,  37, 290,  92);

	s63 = new Rail(290, 133, 290, 174);

	s64 = new Rail(290, 298, 290, 339);

	s65 = new Rail(290, 380, 290, 421);

	s66 = new Rail(330,  37, 330,  92);

	s67 = new Rail(330, 133, 330, 174);

	s68 = new Rail(330, 298, 330, 339);

	s69 = new Rail(330, 380, 330, 421);

	s70 = new Rail(371,  92, 371, 133);

	s71 = new Rail(371, 174, 371, 215);
	s72 = new Rail(371, 215, 371, 257);
	s73 = new Rail(371, 257, 371, 298);

	s74 = new Rail(371, 339, 371, 380);

	s75 = new Rail(412,  37, 412,  92);
	s76 = new Rail(412,  92, 412, 133);
	s77 = new Rail(412, 133, 412, 215);
	s78 = new Rail(412, 215, 412, 298);
	s79 = new Rail(412, 298, 412, 339);
	s80 = new Rail(412, 339, 412, 380);

	s81 = new Rail(452, 339, 452, 380);

	s82 = new Rail(480,  37, 480,  92);
	s83 = new Rail(480,  92, 480, 133);

	s84 = new Rail(480, 298, 480, 339);

	s85 = new Rail(480, 380, 480, 421);

	// ghost castle
	s86 = new Rail(280, 222, 309, 222);  // horizontal, the left one - 1 pixel too short, so it is a one-way outwards
	s87 = new Rail(311, 222, 340, 222);  // horizontal, the right one - 1 pixel too short, so it is a one-way outwards
	s88 = new Rail(280, 200, 280, 222);  // vertical, the left one
	s89 = new Rail(310, 175, 310, 222);  // vertical, the middle (long) one - 1 pixel too short, so it usually is a one-way outwards
	s90 = new Rail(340, 200, 340, 222);  // vertical, the right one

	Rail *array_rails_temp[Constants::NUMBER_RAILS] = {s0,  s1,  s2,  s3,  s4,  s5,  s6,  s7,  s8,  s9,
													   s10, s11, s12, s13, s14, s15, s16, s17, s18, s19,
													   s20, s21, s22, s23, s24, s25, s26, s27, s28, s29,
													   s30, s31, s32, s33, s34, s35, s36, s37, s38, s39,
													   s40, s41, s42, s43, s44, s45, s46, s47, s48, s49,
													   s50, s51, s52, s53, s54, s55, s56, s57, s58, s59,
													   s60, s61, s62, s63, s64, s65, s66, s67, s68, s69,
													   s70, s71, s72, s73, s74, s75, s76, s77, s78, s79,
													   s80, s81, s82, s83, s84, s85, s86, s87, s88, s89,
													   s90};
	memcpy(array_rails, array_rails_temp, sizeof(array_rails_temp));
	Rail *array_rails_pills_temp[Constants::NUMBER_RAILS_PILLS] = {s0,  s1,  s2,  s3,  s4,  s5,  s6,  s7,  s8,  s9,
																   s10, s11, s12, s13, s14,
																					   s24, s25, s26, s27, s28, s29,
																   s30, s31, s32, s33, s34, s35, s36, s37, s38, s39,
																   s40, s41, s42, s43, s44, s45, s46, s47, s48, s49,
																   s50, s51, s52, s53, s54, s55, s56, s57,
																		s61, s62,      s64, s65, s66,      s68, s69,
																   s70,                s74, s75, s76, s77, s78, s79,
																   s80, s81, s82, s83, s84, s85};
	memcpy(array_rails_pills, array_rails_pills_temp, sizeof(array_rails_pills_temp));

	pille            = Screen::loadImage("gfx/pille.png", 0);
	ar_superpille[0] = Screen::loadImage("gfx/superpille_1.png", 0);
	ar_superpille[1] = Screen::loadImage("gfx/superpille_2.png", 0);
	ar_superpille[2] = Screen::loadImage("gfx/superpille_3.png", 0);
	ar_superpille[3] = Screen::loadImage("gfx/superpille_3.png", 0);
	ar_superpille[4] = Screen::loadImage("gfx/superpille_2.png", 0);
	superpille = ar_superpille[cnt_pill_animation];
	level = Level::getInstance();
}

Labyrinth::~Labyrinth(){
	SDL_FreeSurface(pille);
	SDL_FreeSurface(score);
	SDL_FreeSurface(infoFruit);
	SDL_FreeSurface(initText);
	SDL_FreeSurface(pillSurface);
	SDL_FreeSurface(bgSurface);
	if(level) {
		level->cleanUpInstance();
		level = NULL;
	}
}

void Labyrinth::draw_blocks() {
  	SDL_Rect b1, b2;
  	b1.x = Constants::LEFT_TUNNEL_BLOCK_X;
 	b2.x = Constants::RIGHT_TUNNEL_BLOCK_X;
  	b1.y = b2.y = Constants::TUNNEL_BLOCK_Y;
  	b1.w = b2.w = Constants::TUNNEL_BLOCK_WIDTH;
  	b1.h = b2.h = Constants::TUNNEL_BLOCK_HEIGHT;

	Screen::getInstance()->fillRect(&b1, 0, 0, 0);
	Screen::getInstance()->fillRect(&b2, 0, 0, 0);
}

void Labyrinth::init_pillen(bool firstInit) {
	if (firstInit) {
		int m = -1;
		int s = 0;
		this->cnt_pills = Constants::NUMBER_PILLS;
		int i_ar_pille_x[26] = {148,162,176,190,204,217,231,245,259,273,287,300,314,327,340,354,368,381,395,409,422,436,449,462,476,490};
		int i_ar_pille_y[29] = {47,61,75,89,102,116,130,143,157,170,184,197,211,225,239,252,266,280,294,308,321,335,349,362,376,390,404,417,431};
		for(int k = 0; k < Constants::NUMBER_RAILS; k++)
			array_rails[k]->numPills = 0;
		for(int i = 0; i < 26; i++) {
			for(int j = 0; j < 29; j++) {
				bool created = false;
				for(int k = 0; k < Constants::NUMBER_RAILS_PILLS; k++) {
					if (array_rails_pills[k]->x1 <= i_ar_pille_x[i]-10 && i_ar_pille_x[i]-10 <= array_rails_pills[k]->x2 && array_rails_pills[k]->y1 <= i_ar_pille_y[j]-10 && i_ar_pille_y[j]-10 <= array_rails_pills[k]->y2) {
						m++;
						pillen[m].x = i_ar_pille_x[i];
						pillen[m].y = i_ar_pille_y[j];
						pillen[m].sichtbar = 1;
						if (((i_ar_pille_x[i]==148)||(i_ar_pille_x[i] == 490)) && ((i_ar_pille_y[j] == 75)||(i_ar_pille_y[j] == 349))) {
							pillen[m].superpille = 1;
							idxSuperpills[s] = m;
							s++;
						} else
							pillen[m].superpille = 0;
						created = true;
						break;
					}
				}
				if (created) {
					for(int k = 0; k < Constants::NUMBER_RAILS; k++) {
						if (array_rails[k]->x1 <= i_ar_pille_x[i]-10 && i_ar_pille_x[i]-10 <= array_rails[k]->x2 && array_rails[k]->y1 <= i_ar_pille_y[j]-10 && i_ar_pille_y[j]-10 <= array_rails[k]->y2) {
							array_rails[k]->idxPills[array_rails[k]->numPills] = m;
							array_rails[k]->numPills++;
						}
					}
				}
			}
		}
	} else {
		// initialization of pills has already taken place, only reset them
		this->cnt_pills = Constants::NUMBER_PILLS;
		for (int i = 0; i < Constants::NUMBER_PILLS; i++)
			pillen[i].sichtbar = 1;
	}
	getBackground();
	if (bgSurface) {
		if (!pillSurface) {
			pillSurface = SDL_CreateRGBSurface(0, bgSurface->w, bgSurface->h, bgSurface->format->BitsPerPixel,
			  bgSurface->format->Rmask, bgSurface->format->Gmask, bgSurface->format->Bmask, bgSurface->format->Amask);
		}
		SDL_BlitSurface(bgSurface, NULL, pillSurface, NULL);
		SDL_Rect dest;
		for (int i = 0; i < Constants::NUMBER_PILLS; i++) {
			if (!pillen[i].superpille) {
				dest.x = (short int) pillen[i].x;
				dest.y = (short int) pillen[i].y;
				dest.w = pille->w;
				dest.h = pille->h;
				SDL_BlitSurface(pille, NULL, pillSurface, &dest);
			}
		}
	}
}

void Labyrinth::draw_pillen() {
	Screen::getInstance()->draw(pillSurface, 0, 0);
	int x, y;
	for (int i = 0; i < 4; i++) {
		if (pillen[idxSuperpills[i]].sichtbar) {
			x = pillen[idxSuperpills[i]].x - 4;
			y = pillen[idxSuperpills[i]].y - 4;
			Screen::getInstance()->draw(superpille, x, y);
			Screen::getInstance()->AddUpdateRects(x, y, superpille->w, superpille->h);
		}
	}
}

int Labyrinth::number_rails() const {
	return Constants::NUMBER_RAILS;
}

void Labyrinth::pill_animation() {
	cnt_pill_animation = (cnt_pill_animation + 1) % 5;
	superpille = ar_superpille[cnt_pill_animation];
}

void Labyrinth::drawScoreValue() {
	if (punktestand != lastPunktestand || !score) {
		ostringstream ostrPunktestand;
		ostrPunktestand.str("0");
		ostrPunktestand << punktestand;
		if (score)
			SDL_FreeSurface(score);
		score = Screen::getTextSurface(Screen::getFont(), ostrPunktestand.str().c_str(), Constants::YELLOW_COLOR);
	}
	Screen::getInstance()->draw_dynamic_content(score, Constants::SCORE_X, Constants::SCORE_VALUE_Y);
}

void Labyrinth::drawLevelNumber() {
	Screen::getInstance()->draw_dynamic_content(levelNumber, Constants::LEVEL_X, Constants::LEVEL_NUMBER_Y);
}

void Labyrinth::increaseBonusStage() {
	if (bonus_stage < 1600)
		bonus_stage <<= 1;  // bit shifting is faster than bonus_stage *= 2;
}

void Labyrinth::resetBonusStage() {
	bonus_stage = 200;
}

void Labyrinth::addScore(int value, int show_x, int show_y) {
	punktestand += value;
	// show the score at the specified position
	ostringstream ostrScore;
	ostrScore << value;
	smallScore = Screen::getTextSurface(Screen::getSmallFont(), ostrScore.str().c_str(), Constants::WHITE_COLOR);
	smallScore_x = show_x - (smallScore->w >> 1);
	smallScore_y = show_y - (smallScore->h >> 1);
	drawSmallScore();
}

void Labyrinth::drawSmallScore() {
	if (smallScore)
		Screen::getInstance()->draw_dynamic_content(smallScore, smallScore_x, smallScore_y);
}

void Labyrinth::hideSmallScore() {
	if (smallScore) {
		Screen::getInstance()->AddUpdateRects(smallScore_x, smallScore_y, smallScore->w, smallScore->h);
		SDL_FreeSurface(smallScore);
		smallScore = NULL;
	}
}

void Labyrinth::addScore(int value) {
	punktestand += value;
}

void Labyrinth::addBonusScore(int show_x, int show_y) {
	addScore(bonus_stage, show_x, show_y);
}

int Labyrinth::getScore() {
	return punktestand;
}

int Labyrinth::getLevelNumber() {
	return level->getLevelNumber();
}

void Labyrinth::removePill(int idxPill) {
	if (idxPill >= 0) {
		pillen[idxPill].sichtbar = 0;
		if (pillSurface && bgSurface) {
			SDL_Rect dest;
			dest.x = (short int) pillen[idxPill].x;
			dest.y = (short int) pillen[idxPill].y;
			dest.w = (short int) pille->w;
			dest.h = (short int) pille->h;
			SDL_BlitSurface(bgSurface, &dest, pillSurface, &dest);
		}
		--cnt_pills;
		if(cnt_pills == level->getPillLimit()) {
			for(unsigned int i = 0; i < vec_observer.size(); i++)
				vec_observer.at(i)->setPanicMode(true);
		}
	}
}

int Labyrinth::getNumRemainingPills() const {
	return cnt_pills;
}

void Labyrinth::setInitText(const char *text, int color) {
	initText = Screen::getTextSurface(Screen::getFont(), text, Constants::getIndexedColor(color));
}

void Labyrinth::drawInitText() {
	if(initText)
		Screen::getInstance()->draw_dynamic_content(initText, Constants::INIT_TEXT_X-(initText->w >> 1), Constants::INIT_TEXT_Y-(initText->h >> 1));
}

void Labyrinth::hideInitText() {
	if (initText) {
		Screen::getInstance()->AddUpdateRects(Constants::INIT_TEXT_X-(initText->w >> 1), Constants::INIT_TEXT_Y-(initText->h >> 1), initText->w, initText->h);
		SDL_FreeSurface(initText);
		initText = NULL;
	}
}

void Labyrinth::resetAllFigures() {
	for(int i = 0; i < Constants::TOTAL_NUM_GHOSTS; ++i)
		Ghost::getGhostArray()[i]->reset();
	Ghost::getGhostArray()[0]->set_leader(1);  // Blinky is the reference for redrawing
	Pacman::getInstance()->reset();
}

void Labyrinth::nextLevel() {
	hideFruit();
	drawScoreValue();
	Screen::getInstance()->addUpdateClipRect();
	Screen::getInstance()->Refresh();
	SDL_Delay(Constants::WAIT_FOR_NEW_LEVEL);
	level->nextLevel();
	resetLevel();
}

void Labyrinth::resetLevel(int level) {
	Screen::getInstance()->clear();
	hideFruit();
	resetAllFigures();
	if (level >= 1)
		this->level->setLevel(level);
	init_pillen(level <= 1);
	draw_pillen();  // including background
	loadLevelFruit();
	startFruitRandomizer(true);
	ostringstream ostrLevel;
	if (level == 1) {
		setInitText("Get Ready!");
	} else {
		ostrLevel << "Level " << this->level->getLevelNumber();	
		setInitText(ostrLevel.str().c_str());
	}
	if (levelNumber)
		SDL_FreeSurface(levelNumber);
	ostrLevel.str("");
	ostrLevel << this->level->getLevelNumber();	
	levelNumber = Screen::getTextSurface(Screen::getVeryLargeFont(), /*charLevel*/ostrLevel.str().c_str(), Constants::WHITE_COLOR);
	drawLevelNumber();
	Screen::getInstance()->addUpdateClipRect();
	Screen::getInstance()->Refresh();
	for(unsigned int i = 0; i < vec_observer.size(); i++)
		vec_observer.at(i)->setPanicMode(false);
}

void Labyrinth::loadLevelFruit() {
	fruit = NULL;
	switch(level->getLevelNumber()) {
		case 1:
			setFruitBonus(100);
			infoFruit = Screen::loadImage("gfx/cherry.png", 255);
			break;
		case 2:
			setFruitBonus(300);
			infoFruit = Screen::loadImage("gfx/strawberry.png", 255);
			break;
		case 3:
		case 4:
			setFruitBonus(500);
			infoFruit = Screen::loadImage("gfx/orange.png", 255);
			break;
		case 5:
		case 6:
			setFruitBonus(700);
			infoFruit = Screen::loadImage("gfx/apple.png", 255);
			break;
		case 7:
		case 8:
			setFruitBonus(1000);
			infoFruit = Screen::loadImage("gfx/grapes.png", 255);
			break;
		case 9:
		case 10:
			setFruitBonus(2000);
			infoFruit = Screen::loadImage("gfx/banana.png", 255);
			break;
		case 11:
		case 12:
			setFruitBonus(3000);
			infoFruit = Screen::loadImage("gfx/pear.png", 255);
			break;
		default:
			setFruitBonus(5000);
			infoFruit = Screen::loadImage("gfx/key.png", 255);
	};
	cnt_displayed_fruits = 0;
	drawInfoFruits();
}

void Labyrinth::startFruitRandomizer(int new_level) {
	if(new_level)
		cnt_displayed_fruits = 0;
	if(cnt_displayed_fruits >= 2)
		return;
	fruit_display_time = 0;
	next_fruit = ((rand() % 4) + 5) * 10;
	next_fruit = getNumRemainingPills() - next_fruit;
}

void Labyrinth::checkFruit(int ms) {
	if(fruit) {
		fruit_display_time -= ms;
		if (fruit_display_time <= 0)
			hideFruit();
	} else {
		if(getNumRemainingPills() <= next_fruit) {
			fruit = infoFruit;
			fruit_display_time = level->getFruitDisplayTime(); //10000;
			++cnt_displayed_fruits;
			drawInfoFruits();
		}
	}
}

void Labyrinth::hideFruit() {
	if (fruit) {
		Screen::getInstance()->AddUpdateRects(Constants::FRUIT_X, Constants::FRUIT_Y, fruit->w, fruit->h);
		fruit = NULL;
		fruit_display_time = 0;
		if (cnt_displayed_fruits < 2) {
			startFruitRandomizer(false);
		} else {
			next_fruit = -1;  // never again in this level
		}
	}
}

int Labyrinth::fruitIsDisplayed() {
	return (fruit != NULL);
}

// set fruit bonus
void Labyrinth::setFruitBonus(int fruit_bonus) {
	this->fruit_bonus = fruit_bonus;
}

// get fruit bonus
int Labyrinth::getFruitBonus() const {
	return fruit_bonus;
}

void Labyrinth::drawFruit() {
	if (fruit)
		Screen::getInstance()->draw_dynamic_content(fruit, Constants::FRUIT_X, Constants::FRUIT_Y);
}

void Labyrinth::drawInfoFruits() {
	if (infoFruit) {
		for (int i = 0; i < 2-cnt_displayed_fruits; ++i)
			Screen::getInstance()->draw(infoFruit, Constants::INFO_FRUITS_X+i*(infoFruit->w+Constants::INFO_FRUITS_DISTANCE), Constants::INFO_FRUITS_Y);
		Screen::getInstance()->AddUpdateRects(Constants::INFO_FRUITS_X, Constants::INFO_FRUITS_Y, 2*infoFruit->w + Constants::INFO_FRUITS_DISTANCE, infoFruit->h);
	}
}

void Labyrinth::getRailsForPoint(int x, int y, int *left, int *right, int *up, int *down) {
	*left = *right = *up = *down = -1;
	for (int i = 0; i < Constants::NUMBER_RAILS; ++i) {
		if (array_rails[i]->y1 == y && array_rails[i]->y2 == y) {
			if (array_rails[i]->x1 <= x && x <= array_rails[i]->x2) {
				// overlapping horizontal rail - left or right or both
				if (array_rails[i]->x1 < x)
					*left = i;
				if (x < array_rails[i]->x2)
					*right = i;
			}
		} else if (array_rails[i]->x1 == x && array_rails[i]->x2 == x) {
			if (array_rails[i]->y1 <= y && y <= array_rails[i]->y2) {
				// overlapping vertical rail - up or down or both
				if (array_rails[i]->y1 < y)
					*up = i;
				if (y < array_rails[i]->y2)
					*down = i;
			}
		}
		if (*left>=0 && *right>=0 && *up>=0 && *down>=0)
			return;
	}
}

Sounds* Labyrinth::getSounds() {
	std::cerr << "Labyrinth::getSounds() is deprecated! Please use Sounds::getInstance() instead." << std::endl;
	return Sounds::getInstance();
}

void Labyrinth::resetScore() {
	punktestand = 0;
	lastPunktestand = 0;
	if (score) {
		SDL_FreeSurface(score);
		score = NULL;
	}
}

SDL_Surface* Labyrinth::get_superpill_sf() {
	return superpille;
}

SDL_Surface *Labyrinth::getBackground() {
	if (!bgSurface) {
		bgSurface = Screen::loadImage("gfx/hintergrund2.png");
	}
	return bgSurface;
}

void Labyrinth::setLabyrinthObserver(LabyrinthObserver* labyrinthObserver) {
	this->vec_observer.push_back(labyrinthObserver);
}
