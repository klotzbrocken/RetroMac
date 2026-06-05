#include "ghost_figur.h"
#include "game.h"
#include <stdlib.h>

int Ghost::was_moving_leader = 1;
Ghost **Ghost::ghostArray = NULL;

Ghost **Ghost::getGhostArray() {
	if (!ghostArray) {
		ghostArray = new Ghost*[Constants::TOTAL_NUM_GHOSTS];
		ghostArray[0] = Blinky::getInstance();
		ghostArray[1] = Pinky::getInstance();
		ghostArray[2] = Inky::getInstance();
		ghostArray[3] = Clyde::getInstance();
	}
	return ghostArray;
}
void Ghost::cleanUpGhostArray() {
	if (ghostArray) {
		Blinky::cleanUpInstance();
		Pinky::cleanUpInstance();
		Inky::cleanUpInstance();
		Clyde::cleanUpInstance();
		delete [] ghostArray;
		ghostArray = NULL;
	}
}

Ghost::Ghost(int init_x, int init_y, int init_intelligence,
             Direction init_direction, int init_up_down, int ghost_ident):
	Figur(init_x, init_y, Constants::GHOSTS_V_NORMAL),
	its_leader(0),
	initial_intelligence(init_intelligence),
	initial_direction(init_direction),
	initial_up_down(init_up_down),
	ghost_ident(ghost_ident),
	idxCurrentRail(-1),  // should first be determined
	panicMode(0)
{
	direction = init_direction;
	intelligence = init_intelligence;
	up_down = init_up_down;
	set_hunter(GHOST);
	// Surfaces
	if(ghost_ident == BLINKY) {
		ghost_1 = Screen::loadImage("gfx/blinky_1.png", 255);
		ghost_2 = Screen::loadImage("gfx/blinky_2.png", 255);
		idxCurrentRail = 16;
	}
	else if(ghost_ident == PINKY) {
		ghost_1 = Screen::loadImage("gfx/pinky_1.png", 255);
		ghost_2 = Screen::loadImage("gfx/pinky_2.png", 255);
		idxCurrentRail = 89;
	}
	else if(ghost_ident == INKY) {
		ghost_1 = Screen::loadImage("gfx/inky_1.png", 255);
		ghost_2 = Screen::loadImage("gfx/inky_2.png", 255);
		idxCurrentRail = 88;
	}
	else if(ghost_ident == CLYDE) {
		ghost_1 = Screen::loadImage("gfx/clyde_1.png", 255);
		ghost_2 = Screen::loadImage("gfx/clyde_2.png", 255);
		idxCurrentRail = 90;
	}
	augen_0        = Screen::loadImage("gfx/augen_0.png", 0);
	augen_1        = Screen::loadImage("gfx/augen_1.png", 0);
	augen_2        = Screen::loadImage("gfx/augen_2.png", 0);
	augen_3        = Screen::loadImage("gfx/augen_3.png", 0);
	escape_1       = Screen::loadImage("gfx/escaping_ghost_1.png", 255);
	escape_2       = Screen::loadImage("gfx/escaping_ghost_2.png", 255);
	escape_white_1 = Screen::loadImage("gfx/escaping_ghost_white_1.png", 0);
	escape_white_2 = Screen::loadImage("gfx/escaping_ghost_white_2.png", 0);
	ar_ghost[0] = ghost_1;
	ar_ghost[1] = ghost_2;
	ar_ghost[2] = escape_white_1;
	ar_ghost[3] = escape_white_2;
	num_animation_frames = 2;
	idx_animation = 1;
	ghost_sf = ar_ghost[idx_animation];
	Labyrinth::getInstance()->setLabyrinthObserver(this);
}

Ghost::~Ghost() {
	SDL_FreeSurface(ghost_1);
	SDL_FreeSurface(ghost_2);
	SDL_FreeSurface(augen_0);
	SDL_FreeSurface(augen_1);
	SDL_FreeSurface(augen_2);
	SDL_FreeSurface(augen_3);
	SDL_FreeSurface(escape_1);
	SDL_FreeSurface(escape_2);
	SDL_FreeSurface(escape_white_1);
	SDL_FreeSurface(escape_white_2);
}

void Ghost::draw() {
	if (this->visible) {
		if (this->get_hunter() != NONE)
			Screen::getInstance()->draw(this->ghost_sf, this->x, this->y);
		if (this->get_hunter() != PACMAN) {
			switch(this->get_direction()) {
				case LEFT:
					Screen::getInstance()->draw(augen_0, this->x, this->y);
					break;
				case UP:
					Screen::getInstance()->draw(augen_1, this->x, this->y);
					break;
				case RIGHT:
					Screen::getInstance()->draw(augen_2, this->x, this->y);
					break;
				case DOWN:
					Screen::getInstance()->draw(augen_3, this->x, this->y);
					break;
				default:
					Screen::getInstance()->draw(augen_0, this->x, this->y);
					break;
			}
		}
	}
}

void Ghost::animation() {
	idx_animation = (idx_animation + 1) % num_animation_frames;
	this->ghost_sf = ar_ghost[idx_animation];
}

void Ghost::set_leader(bool leader) {
	its_leader = leader;
}

void Ghost::set_leader() {
	for(int i = 0; i < Constants::TOTAL_NUM_GHOSTS; ++i) {
		if(getGhostArray()[i]->getGhostIdent() == this->getGhostIdent())
			getGhostArray()[i]->set_leader(true);
		else
			getGhostArray()[i]->set_leader(false);
	}}

void Ghost::move_dir(int ms, int direction, int max_links, int max_oben, int max_rechts, int max_unten) {
	if(direction == LEFT)
		move_left(ms, max_links);
	if(direction == UP)
		move_up(ms, max_oben);
	if(direction == RIGHT)
		move_right(ms, max_rechts);
	if(direction == DOWN)
		move_down(ms, max_unten);
	if(its_leader) {
		if(this->was_moving())
			was_moving_leader = 1;
		else
			was_moving_leader = 0;
	}
}

void Ghost::move(int ms) {
	this->move_on_rails(ms, Labyrinth::getInstance()->array_rails);
	if (last_x != x || last_y != y)
		this->addUpdateRect();
}

int Ghost::direction_to_point(int target_x, int target_y) {
	int dx = abs(target_x - this->x);
	int dy = abs(target_y - this->y);
	if (dx > dy) {
		return (target_x - this->x > 0) ? RIGHT : LEFT;
	} else {
		return (target_y - this->y > 0) ? DOWN : UP;
	}
}

int Ghost::alternative_direction_to_point(int target_x, int target_y) {
	int dx = abs(target_x - this->x);
	int dy = abs(target_y - this->y);
	if (dx > dy) {
		// actually, here, a horizontal direction would be the best one, but what if it's not available?
		return (target_y - this->y > 0) ? DOWN : UP;
	} else {
		// actually vertical, alternative will be horizontal
		return (target_x - this->x > 0) ? RIGHT : LEFT;
	}
}

int Ghost::get_intelligence() const {
	return intelligence;
}

int Ghost::choose_direction(Direction * sammel_richtung, int richtung_pacman, int sammel_counter, int intelligence) {
	int idx_dir_pacman = -1;
	int zufallswert;
	int idx_direction;
	int castle_direction;

	if(sammel_counter == 1)
		return sammel_richtung[0];

	if (this->get_hunter() == NONE) {
		// try to return to the ghost castle
		castle_direction = this->direction_to_point(Constants::CASTLE_X, Constants::CASTLE_Y);
		for (int i = 0; i < sammel_counter; ++i) {
			if (sammel_richtung[i] == castle_direction)
				return castle_direction;
		}
		// try an alternative direction
		castle_direction = this->alternative_direction_to_point(Constants::CASTLE_X, Constants::CASTLE_Y);
		for (int i = 0; i < sammel_counter; ++i) {
			if (sammel_richtung[i] == castle_direction)
				return castle_direction;
		}
		// if neither the exact nor the alternative direction can be taken, then choose randomly
		zufallswert = (rand() % 100 + 1);
		return sammel_richtung[zufallswert%sammel_counter];
	}

	for(int i = 0; i < sammel_counter; ++i) {
		if(sammel_richtung[i] == richtung_pacman){
			idx_dir_pacman = i;
		}
	}
	zufallswert = (rand() % 100 + 1);
	if (this->get_hunter() == PACMAN) {
		if (idx_dir_pacman == -1 || zufallswert > intelligence) {
			return sammel_richtung[zufallswert%sammel_counter];
		} else {
			idx_direction = zufallswert % (sammel_counter-1);
			if (idx_direction == idx_dir_pacman)
				++idx_direction;
			return sammel_richtung[idx_direction];
		}
	} else {
		if(idx_dir_pacman != -1) {
			if(zufallswert <= intelligence)
				return richtung_pacman;
		}
		return sammel_richtung[zufallswert%sammel_counter];
	}
}

void Ghost::move_on_rails(int ms, Rail **ar_s) {
	bool moved = false;
	Direction old_dir = get_direction();
	Direction sammel_richtung[3];
	int sammel_counter = 0;
	int idxLeft = -1, idxRight = -1, idxUp = -1, idxDown = -1;
	if (idxCurrentRail >= 0) {
		// first, try to keep moving on the current rail
		if (ar_s[idxCurrentRail]->y1 == ar_s[idxCurrentRail]->y2) {
			// horizontal rail
			if (old_dir == LEFT && x > ar_s[idxCurrentRail]->x1 - ((idxCurrentRail==87)?1:0)) {
				move_left(ms, ar_s[idxCurrentRail]->x1 - ((idxCurrentRail==87)?1:0));
				moved = true;
			} else if (old_dir == RIGHT && x < ar_s[idxCurrentRail]->x2 + ((idxCurrentRail==86)?1:0)) {
				move_right(ms, ar_s[idxCurrentRail]->x2 + ((idxCurrentRail==86)?1:0));
				moved = true;
			}
		} else {
			// vertical rail
			if (old_dir == UP && y > ar_s[idxCurrentRail]->y1 - ((idxCurrentRail==89)?1:0)) {
				this->move_up(ms, ar_s[idxCurrentRail]->y1 - ((idxCurrentRail==89)?1:0));
				moved = true;
			} else if (old_dir == DOWN && y < ar_s[idxCurrentRail]->y2) {
				this->move_down(ms, ar_s[idxCurrentRail]->y2);
				moved = true;
			}
		}
	}
	if (!moved) {
		// check the tunnel
		if ((old_dir != RIGHT) && (x <= Constants::LEFT_TUNNEL_BLOCK_X) && (y == Constants::TUNNEL_BLOCK_Y)) {
	 		x = Constants::RIGHT_TUNNEL_BLOCK_X;
	 		cur_x = x << 10;
	 		old_dir = LEFT;
	 		idxCurrentRail = 22;
	 		moved = true;
		} else if ((old_dir != LEFT) && (x >= Constants::RIGHT_TUNNEL_BLOCK_X) && (y == Constants::TUNNEL_BLOCK_Y)) {
	 		x = Constants::LEFT_TUNNEL_BLOCK_X;
	 		cur_x = x << 10;
	 		old_dir = RIGHT;
	 		idxCurrentRail = 19;
	 		moved = true;
		}
	}
	if (!moved) {
		if (idxCurrentRail==89 && old_dir==DOWN && y>=ar_s[89]->y2) {
			// special case: at the bottom of the castle's vertical center rail, the ghost must invert it's direction (i.e. go up again)
			sammel_richtung[0] = UP;
			sammel_counter = 1;
			// make an eyes-only ghost normal again
			if (get_hunter() == NONE) {
				set_hunter(GHOST);
				Game::getInstance()->checkMusic();
			}
		} else if (up_down) {
			sammel_richtung[sammel_counter] = ((old_dir==UP) ? DOWN : UP);
			++sammel_counter;
			up_down--;
		} else {
			// Find the rails that the ghost may take next
			Labyrinth::getInstance()->getRailsForPoint(x, y, &idxLeft, &idxRight, &idxUp, &idxDown);
			// eliminate the direction the ghost came from
			switch (old_dir) {
			case LEFT:
				idxRight = -1;
				break;
			case RIGHT:
				idxLeft = -1;
				break;
			case UP:
				idxDown = -1;
				break;
			case DOWN:
				idxUp = -1;
				break;
			}
			// for a returning eyes-only ghost, open the door to the castle
			if (get_hunter() == NONE && x == ar_s[89]->x1 && y == ar_s[89]->y1-1)
				idxDown = 89;
			// eliminate the directions where the rail end has already been reached
			if (old_dir == LEFT && idxLeft>=0 && x <= ar_s[idxLeft]->x1 && ar_s[idxLeft]->y1==ar_s[idxLeft]->y2)
				idxLeft = -1;
			if (old_dir == RIGHT && idxRight>=0 && x >= ar_s[idxRight]->x2 && ar_s[idxLeft]->y1==ar_s[idxLeft]->y2)
				idxRight = -1;
			if (old_dir == UP && idxUp>=0 && y <= ar_s[idxUp]->y1 && ar_s[idxLeft]->x1==ar_s[idxLeft]->x2)
				idxUp = -1;
			if (old_dir == DOWN && idxDown>=0 && y >= ar_s[idxDown]->y2 && ar_s[idxLeft]->x1==ar_s[idxLeft]->x2)
				idxDown = -1;
			// insert the directions to the array
			if (idxLeft >= 0) {
				sammel_richtung[sammel_counter] = LEFT;
				++sammel_counter;
			}
			if (idxRight >= 0) {
				sammel_richtung[sammel_counter] = RIGHT;
				++sammel_counter;
			}
			if (idxUp >= 0) {
				sammel_richtung[sammel_counter] = UP;
				++sammel_counter;
			}
			if (idxDown >= 0) {
				sammel_richtung[sammel_counter] = DOWN;
				++sammel_counter;
			}
		}
	}
	if (!moved && sammel_counter > 0) {
		int richtung_pacman = this->direction_to_point(Pacman::getInstance()->x, Pacman::getInstance()->y);
		int new_dir = choose_direction(sammel_richtung, richtung_pacman, sammel_counter, get_intelligence());
		if (new_dir==LEFT && idxLeft>=0)
			idxCurrentRail = idxLeft;
		if (new_dir==RIGHT && idxRight>=0)
			idxCurrentRail = idxRight;
		if (new_dir==UP && idxUp>=0)
			idxCurrentRail = idxUp;
		if (new_dir==DOWN && idxDown>=0)
			idxCurrentRail = idxDown;
		int maxLeft  = ((idxCurrentRail>=0) ? ar_s[idxCurrentRail]->x1 : 0);
		int maxRight = ((idxCurrentRail>=0) ? ar_s[idxCurrentRail]->x2 : 10000);
		int maxUp    = ((idxCurrentRail>=0) ? ar_s[idxCurrentRail]->y1 : 0);
		int maxDown  = ((idxCurrentRail>=0) ? ar_s[idxCurrentRail]->y2 : 10000);
		move_dir(ms, new_dir, maxLeft, maxUp, maxRight, maxDown);
	}
}

void Ghost::reset() {
	x = initial_x;
	y = initial_y;
	speed = initial_v;
	last_x = initial_x;
	last_y = initial_y;
	cur_x = initial_x << 10;
	cur_y = initial_y << 10;
	direction = initial_direction;
	intelligence = initial_intelligence;
	up_down = initial_up_down;
	this->set_hunter(GHOST);
	if (ghost_ident == BLINKY)
		idxCurrentRail = 16;
	if (ghost_ident == PINKY)
		idxCurrentRail = 89;
	if (ghost_ident == INKY)
		idxCurrentRail = 88;
	if (ghost_ident == CLYDE)
		idxCurrentRail = 90;
	visible = true;
}

void Ghost::addUpdateRect() {
	Screen::getInstance()->AddUpdateRects(least(x,last_x), least(y,last_y), ghost_sf->w + abs(x-last_x), ghost_sf->h + abs(y-last_y));
}

SDL_Surface* Ghost::get_Surface() const {
	return ghost_sf;
}

Figur::Hunter Ghost::get_hunter() const {
	return hunter;
}

void Ghost::set_hunter(Hunter hunter) {
	if(hunter == PACMAN) {
		this->set_speed(Constants::GHOSTS_V_SLOW);
		ar_ghost[0] = escape_1;
		ar_ghost[1] = escape_2;
	} else {
		this->set_speed(panicMode ? Constants::GHOSTS_V_FAST : Constants::GHOSTS_V_NORMAL);
		ar_ghost[0] = ghost_1;
		ar_ghost[1] = ghost_2;
	}
	num_animation_frames = 2;
	this->hunter = hunter;
}

bool Ghost::touched() {
	if(get_hunter() == PACMAN) {
		// ghost has been eaten by pacman
		hunter = NONE;
		set_speed(panicMode ? Constants::GHOSTS_V_FAST : Constants::GHOSTS_V_NORMAL);
		set_leader();
		setVisibility(false);
		Pacman::getInstance()->setVisibility(false);
		Labyrinth::getInstance()->addBonusScore(x + (ghost_sf->w >> 1), y + (ghost_sf->h >> 1));
		Labyrinth::getInstance()->increaseBonusStage();
		Game::getInstance()->sleep(Constants::PAUSE_AFTER_BONUS_SCORE);
		Sounds::getInstance()->playSingleSound(Sounds::EAT_GHOST);
	}
	if(get_hunter() == NONE)
		return false;  // no problem for pacman
	return true;
}

void Ghost::blink() {
	if(get_hunter() == PACMAN) {
		num_animation_frames = 4;
	}
}

Ghost::Ghosts Ghost::getGhostIdent() const {
	return (Ghosts)ghost_ident;
}

void Ghost::setPanicMode(int set) {
	panicMode = set;
	if(this->hunter != PACMAN) 
		this->set_speed(panicMode ? Constants::GHOSTS_V_FAST : Constants::GHOSTS_V_NORMAL);
}

// --- BLINKY ---
Blinky *Blinky::instance = NULL;
Blinky *Blinky::getInstance() {
	if (!instance) {
		instance = new Blinky();
	}
	return instance;
}
void Blinky::cleanUpInstance() {
	if (instance) {
		delete instance;
		instance = NULL;
	}
}
Blinky::Blinky():
	Ghost(Constants::BLINKY_INITIAL_X, Constants::BLINKY_INITIAL_Y, Constants::INTELLIGENCE_BLINKY, Figur::LEFT, Constants::INIT_UP_DOWN_BLINKY, Ghost::BLINKY)
{}

// --- PINKY ---
Pinky *Pinky::instance = NULL;
Pinky *Pinky::getInstance() {
	if (!instance) {
		instance = new Pinky();
	}
	return instance;
}
void Pinky::cleanUpInstance() {
	if (instance) {
		delete instance;
		instance = NULL;
	}
}
Pinky::Pinky():
	Ghost(Constants::PINKY_INITIAL_X, Constants::PINKY_INITIAL_Y, Constants::INTELLIGENCE_PINKY, Figur::UP, Constants::INIT_UP_DOWN_PINKY, Ghost::PINKY)
{}

// --- INKY ---
Inky *Inky::instance = NULL;
Inky *Inky::getInstance() {
	if (!instance) {
		instance = new Inky();
	}
	return instance;
}
void Inky::cleanUpInstance() {
	if (instance) {
		delete instance;
		instance = NULL;
	}
}
Inky::Inky():
	Ghost(Constants::INKY_INITIAL_X, Constants::INKY_INITIAL_Y, Constants::INTELLIGENCE_INKY, Figur::UP, Constants::INIT_UP_DOWN_INKY, Ghost::INKY)
{}

// --- CLYDE ---
Clyde *Clyde::instance = NULL;
Clyde *Clyde::getInstance() {
	if (!instance) {
		instance = new Clyde();
	}
	return instance;
}
void Clyde::cleanUpInstance() {
	if (instance) {
		delete instance;
		instance = NULL;
	}
}
Clyde::Clyde():
	Ghost(Constants::CLYDE_INITIAL_X, Constants::CLYDE_INITIAL_Y, Constants::INTELLIGENCE_CLYDE, Figur::UP, Constants::INIT_UP_DOWN_CLYDE, Ghost::CLYDE)
{}
