#include "pacman_figur.h"
#include "ghost_figur.h"
#include "math.h"
#include <iostream>

Pacman *Pacman::instance = NULL;

Pacman *Pacman::getInstance() {
	if (!instance) {
		instance = new Pacman();
	}
	return instance;
}

void Pacman::cleanUpInstance() {
	if (instance) {
		delete instance;
		instance = NULL;
	}
}

Pacman::Pacman():
	Figur(Constants::PACMAN_INITIAL_X, Constants::PACMAN_INITIAL_Y, Constants::PACMAN_V_FAST),
	animation(0),
	cnt_animation(0),
	dying(0),
	die_counter(0),
	remainingLives(Constants::INITIAL_LIVES),
	idxCurrentRail(33)
{
	wechsel_x = Constants::PACMAN_INITIAL_X;
	wechsel_y = Constants::PACMAN_INITIAL_Y;
	direction = LEFT;
	direction_pre = LEFT;
	pacman_normal   = Screen::loadImage("gfx/pacman.png", 255);
	pacman_links_1  = Screen::loadImage("gfx/pacman_links_1.png", 255);
    pacman_links_2  = Screen::loadImage("gfx/pacman_links_2.png", 255);
    pacman_oben_1   = Screen::loadImage("gfx/pacman_oben_1.png", 255);
    pacman_oben_2   = Screen::loadImage("gfx/pacman_oben_2.png", 255);
    pacman_rechts_1 = Screen::loadImage("gfx/pacman_rechts_1.png", 255);
    pacman_rechts_2 = Screen::loadImage("gfx/pacman_rechts_2.png", 255);
    pacman_unten_1  = Screen::loadImage("gfx/pacman_unten_1.png", 255);
    pacman_unten_2  = Screen::loadImage("gfx/pacman_unten_2.png", 255);
	// initialize all pacman images
    ar_pacman_links[0] = pacman_links_1;
    ar_pacman_links[1] = pacman_links_2;
    ar_pacman_links[2] = pacman_links_1;
    ar_pacman_links[3] = pacman_normal;

    ar_pacman_oben[0] = pacman_oben_1;
    ar_pacman_oben[1] = pacman_oben_2;
    ar_pacman_oben[2] = pacman_oben_1;
    ar_pacman_oben[3] = pacman_normal;

    ar_pacman_rechts[0] = pacman_rechts_1;
    ar_pacman_rechts[1] = pacman_rechts_2;
    ar_pacman_rechts[2] = pacman_rechts_1;
    ar_pacman_rechts[3] = pacman_normal;

    ar_pacman_unten[0] = pacman_unten_1;
    ar_pacman_unten[1] = pacman_unten_2;
    ar_pacman_unten[2] = pacman_unten_1;
    ar_pacman_unten[3] = pacman_normal;

    ar_pacman_die[0]  = Screen::loadImage("gfx/pacman_die_1.png",  255);
    ar_pacman_die[1]  = Screen::loadImage("gfx/pacman_die_2.png",  255);
    ar_pacman_die[2]  = Screen::loadImage("gfx/pacman_die_3.png",  255);
    ar_pacman_die[3]  = Screen::loadImage("gfx/pacman_die_4.png",  255);
    ar_pacman_die[4]  = Screen::loadImage("gfx/pacman_die_5.png",  255);
    ar_pacman_die[5]  = Screen::loadImage("gfx/pacman_die_6.png",  255);
	ar_pacman_die[6]  = Screen::loadImage("gfx/pacman_die_10.png", 255);
	ar_pacman_die[7]  = Screen::loadImage("gfx/pacman_die_10.png", 255);
	ar_pacman_die[8]  = Screen::loadImage("gfx/pacman_die_10.png", 255);
	ar_pacman_die[9]  = Screen::loadImage("gfx/pacman_die_7.png",  255);
    ar_pacman_die[10] = Screen::loadImage("gfx/pacman_die_8.png",  255);
    ar_pacman_die[11] = Screen::loadImage("gfx/pacman_die_9.png",  255);
    ar_pacman_die[12] = Screen::loadImage("gfx/pacman_die_7.png",  255);
    ar_pacman_die[13] = Screen::loadImage("gfx/pacman_die_8.png",  255);
    ar_pacman_die[14] = Screen::loadImage("gfx/pacman_die_9.png",  255);
    ar_pacman_die[15] = Screen::loadImage("gfx/pacman_die_9.png",  255);

	pacman_sf = ar_pacman_links[0];
}

Pacman::~Pacman() {
	SDL_FreeSurface(pacman_normal);
	SDL_FreeSurface(pacman_links_1);
	SDL_FreeSurface(pacman_links_2);
	SDL_FreeSurface(pacman_oben_1);
	SDL_FreeSurface(pacman_oben_2);
	SDL_FreeSurface(pacman_rechts_1);
	SDL_FreeSurface(pacman_rechts_2);
	SDL_FreeSurface(pacman_unten_1);
	SDL_FreeSurface(pacman_unten_2);
	for(int i = 0; i < 13; i++)
		SDL_FreeSurface(ar_pacman_die[i]);
}

void Pacman::draw() {
	if (visible) {
		animate();
		Screen::getInstance()->draw(pacman_sf, x, y);
	}
}

void Pacman::checkAnimationChange() {
	if (abs(x-wechsel_x)>=Constants::PACMAN_WECHSEL_RATE ||
	    abs(y-wechsel_y)>=Constants::PACMAN_WECHSEL_RATE ||
	    directionChanged)
	{
		wechsel_x = x;
		wechsel_y = y;
		animation = 1;
	}
}

void Pacman::move(int ms) {
	move_on_rails(ms, Labyrinth::getInstance()->array_rails);
	if (last_x != x || last_y != y)
		addUpdateRect();
}
void Pacman::move_left(int ms, int stop_at) {
	Figur::move_left(ms, stop_at);
	checkAnimationChange();
}

void Pacman::move_up(int ms, int stop_at) {
	Figur::move_up(ms, stop_at);
	checkAnimationChange();
}

void Pacman::move_right(int ms, int stop_at) {
	Figur::move_right(ms, stop_at);
	checkAnimationChange();
}

void Pacman::move_down(int ms, int stop_at) {
	Figur::move_down(ms, stop_at);
	checkAnimationChange();
}

void Pacman::left_pic(int cnt_pic) {
	pacman_sf = ar_pacman_links[cnt_pic];
}

void Pacman::up_pic(int cnt_pic) {
	pacman_sf = ar_pacman_oben[cnt_pic];
}

void Pacman::right_pic(int cnt_pic) {
	pacman_sf = ar_pacman_rechts[cnt_pic];
}

void Pacman::down_pic(int cnt_pic) {
	pacman_sf = ar_pacman_unten[cnt_pic];
}

void Pacman::die_pic(int cnt_pic) {
	pacman_sf = ar_pacman_die[cnt_pic];
}
void Pacman::animate() {
	if (animation) {
		animation = 0;
		switch(get_direction()) {
			case 0:
				left_pic(cnt_animation);
				break;
			case 1:
				up_pic(cnt_animation);
				break;
			case 2:
				right_pic(cnt_animation);
				break;
			case 3:
				down_pic(cnt_animation);
				break;
		}
	  	cnt_animation = (cnt_animation + 1) % 4;
	}
}

void Pacman::move_on_rails(int ms, Rail **ar_s) {
	bool moved = false;
	Direction old_dir, new_dir;
	new_dir = old_dir = get_direction();
	if (idxCurrentRail >= 0) {
		// first, try to keep moving on the current rail
		if (ar_s[idxCurrentRail]->y1 == ar_s[idxCurrentRail]->y2) {
			// horizontal rail
			if ((this->direction_pre==LEFT || (old_dir==LEFT && this->direction_pre!=RIGHT)) && this->x > ar_s[idxCurrentRail]->x1) {
				new_dir = LEFT;
				this->move_left(ms, ar_s[idxCurrentRail]->x1);
				moved = true;
			} else if ((this->direction_pre==RIGHT || (old_dir==RIGHT && this->direction_pre!=LEFT)) && this->x < ar_s[idxCurrentRail]->x2) {
				new_dir = RIGHT;
				this->move_right(ms, ar_s[idxCurrentRail]->x2);
				moved = true;
			}
		} else {
			// vertical rail
			if ((this->direction_pre==UP || (old_dir==UP && this->direction_pre!=DOWN)) && this->y > ar_s[idxCurrentRail]->y1) {
				new_dir = UP;
				this->move_up(ms, ar_s[idxCurrentRail]->y1);
				moved = true;
			} else if ((this->direction_pre==DOWN || (old_dir==DOWN && this->direction_pre!=UP)) && this->y < ar_s[idxCurrentRail]->y2) {
				new_dir = DOWN;
				this->move_down(ms, ar_s[idxCurrentRail]->y2);
				moved = true;
			}
		}
	} else {
		this->direction_pre = old_dir;
	}
	if (!moved) {
		// check the tunnel
		if((this->direction_pre != RIGHT) && (this->x <= Constants::LEFT_TUNNEL_BLOCK_X) && (this->y == Constants::TUNNEL_BLOCK_Y)) {
	 		this->x = Constants::RIGHT_TUNNEL_BLOCK_X;
	 		this->cur_x = this->x << 10;
	 		this->direction_pre = LEFT;
	 		idxCurrentRail = 22;
	 		moved = true;
		} else if((this->direction_pre != LEFT) && (this->x >= Constants::RIGHT_TUNNEL_BLOCK_X) && (this->y == Constants::TUNNEL_BLOCK_Y)) {
	 		this->x = Constants::LEFT_TUNNEL_BLOCK_X;
	 		this->cur_x = this->x << 10;
	 		this->direction_pre = RIGHT;
	 		idxCurrentRail = 19;
	 		moved = true;
		}
	}
	if (!moved) {
		// Find the rail that pacman is positioned on. Also, consider the direction that the player wants to move.
		int idxLeft, idxRight, idxUp, idxDown;
		Labyrinth::getInstance()->getRailsForPoint(this->x, this->y, &idxLeft, &idxRight, &idxUp, &idxDown);
		if (idxLeft>=0 && this->x <= ar_s[idxLeft]->x1)
			idxLeft = -1;
		if (idxRight>=0 && ar_s[idxRight]->x2 <= this->x)
			idxRight = -1;
		if (idxUp>=0 && this->y <= ar_s[idxUp]->y1)
			idxUp = 0;
		if (idxDown>=0 && ar_s[idxDown]->y2 <= this->y)
			idxDown = 0;
		bool use_old_dir = false;
		if ((this->direction_pre==LEFT && idxLeft<0) || (this->direction_pre==RIGHT && idxRight<0) || (this->direction_pre==UP && idxUp<0) || (this->direction_pre==DOWN && idxDown<0))
			use_old_dir = true;
		new_dir = use_old_dir ? old_dir : this->direction_pre;
		switch (new_dir) {
		case LEFT:
			if (idxLeft >= 0) {
				move_left(ms, ar_s[idxLeft]->x1);
				idxCurrentRail = idxLeft;
				moved = true;
			}
			break;
		case RIGHT:
			if (idxRight >= 0) {
				move_right(ms, ar_s[idxRight]->x2);
				idxCurrentRail = idxRight;
				moved = true;
			}
			break;
		case UP:
			if (idxUp >= 0) {
				move_up(ms, ar_s[idxUp]->y1);
				idxCurrentRail = idxUp;
				moved = true;
			}
			break;
		case DOWN:
			if (idxDown >= 0) {
				move_down(ms, ar_s[idxDown]->y2);
				idxCurrentRail = idxDown;
				moved = true;
			}
			break;
		}
	}
	if (new_dir != old_dir)
		animation = 1;
	if (!moved)
		stopped();
}

void Pacman::stopped() {
	// if pacman stops, please set it to "normal"
	if (!is_dying()) {
		switch(get_direction()) {
			case Figur::LEFT:
				left_pic(0);
				break;
			case Figur::UP:
				up_pic(0);
				break;
			case Figur::RIGHT:
				right_pic(0);
				break;
			case Figur::DOWN:
				down_pic(0);
				break;
		}
		parking();
	}
}

void Pacman::reset() {
	x = initial_x;
	y = initial_y;
	speed = initial_v;
	last_x = initial_x;
	last_y = initial_y;
	cur_x = initial_x << 10;
	cur_y = initial_y << 10;
	wechsel_x = initial_x;
	wechsel_y = initial_y;
	direction = LEFT;
	direction_pre = LEFT;
	animation = 1;
	cnt_animation = 0;
	idxCurrentRail = 33;
	visible = true;
	dying = 0;
	die_counter = 0;
}

SDL_Surface* Pacman::get_Surface() const {
	return pacman_sf;
}

bool Pacman::ghostTouched() const{
	int x_left_pacman = this->x;
	int y_up_pacman = this->y;
	int x_right_pacman = this->x + this->get_Surface()->w;
	int y_down_pacman = this->y + this->get_Surface()->h;
	int touch_result = 0;

    for(int i = 0; i < 4; i++) {
    	int x_real_ghost = Ghost::getGhostArray()[i]->x + (int)(Ghost::getGhostArray()[i]->get_Surface()->w * 0.5);
		int y_real_ghost = Ghost::getGhostArray()[i]->y + (int)(Ghost::getGhostArray()[i]->get_Surface()->h * 0.5);
		if ((x_real_ghost >= x_left_pacman) && (x_real_ghost <= x_right_pacman) && (y_real_ghost >= y_up_pacman) && (y_real_ghost <= y_down_pacman)) {
			touch_result = Ghost::getGhostArray()[i]->touched();
			if (touch_result != 0) {
				return true;
			}
		}
	}
	return false;
}

void Pacman::check_eat_pills() {
	if(was_moving() && !is_dying()){
		int tmp_last_x = last_x;
		if (this->y == Constants::TUNNEL_BLOCK_Y) {
			if (last_x < 310 && x > 310)  // tunnel crossed - gone out to the left and coming in from the right
				tmp_last_x = Constants::RIGHT_TUNNEL_BLOCK_X + 1;  // if we did not pretend something like this, a pill would be eaten that Pacman did not really pass
			if (last_x > 310 && x < 310)  // tunnel crossed - gone out to the right and coming in from the left
				tmp_last_x = Constants::LEFT_TUNNEL_BLOCK_X - 1;  // if we did not pretend something like this, a pill would be eaten that Pacman did not really pass
		}
		for (int k = 0; k < Labyrinth::getInstance()->array_rails[idxCurrentRail]->numPills; k++) {
			int i = Labyrinth::getInstance()->array_rails[idxCurrentRail]->idxPills[k];
			if(i >= 0 && Labyrinth::getInstance()->pillen[i].sichtbar && ((Labyrinth::getInstance()->pillen[i].x - 10) >= least(this->x,tmp_last_x)) && ((Labyrinth::getInstance()->pillen[i].x - 10) <= greatest(this->x,tmp_last_x)) && ((Labyrinth::getInstance()->pillen[i].y - 10) >= least(this->y,this->last_y)) && ((Labyrinth::getInstance()->pillen[i].y - 10) <= greatest(this->y,this->last_y))) {
				Labyrinth::getInstance()->removePill(i);
				Sounds::getInstance()->playMunch();
				if(Labyrinth::getInstance()->pillen[i].superpille) {
					for(int j = 0; j < 4; ++j) {
						if(Ghost::getGhostArray()[j]->get_hunter() != NONE)  // eaten ghosts still have to return to the castle
							Ghost::getGhostArray()[j]->set_hunter(PACMAN);
					}
					Game::getInstance()->startHuntingMode();
					Labyrinth::getInstance()->addScore(Constants::SUPER_PILL_SCORE);
				} else {
					Labyrinth::getInstance()->addScore(Constants::NORMAL_PILL_SCORE);
				}
				set_speed(Constants::PACMAN_V_SLOW);
				cnt_slow = 15;
				break;
			}
		}
		// only if pacman really has moved
		if(cnt_slow > 0)
			cnt_slow--;
		if(cnt_slow <= 0)
			set_speed(Constants::PACMAN_V_FAST); // make pacman fast again

		// fruit eaten?
		if(Labyrinth::getInstance()->fruitIsDisplayed() && this->y == Constants::FRUIT_Y && ((this->x>=Constants::FRUIT_X && this->last_x<=Constants::FRUIT_X) || (this->x<=Constants::FRUIT_X && this->last_x>=Constants::FRUIT_X))) {
			Sounds::getInstance()->playSingleSound(Sounds::FRUIT);
			Labyrinth::getInstance()->hideFruit();
			Labyrinth::getInstance()->addScore(Labyrinth::getInstance()->getFruitBonus(), Constants::FRUIT_X + 10, Constants::FRUIT_Y + 10);
			setVisibility(false);
			Game::getInstance()->sleep(Constants::PAUSE_AFTER_BONUS_SCORE);
		}
	}
}

void Pacman::set_dying(int dying) {
	this->dying = dying;
}

int Pacman::is_dying() const {
	return dying;
}

int Pacman::die_animation(bool skipSound) {
	if(dying > 1)
		return dying--;
	else {
		if(!die_counter && !skipSound)
			Sounds::getInstance()->playSingleSound(Sounds::DYING);
		this->die_pic(die_counter++);
		if(die_counter == 16) {
			die_counter = 0;
			dying = 0;
		}
		return die_counter;
	}
}

void Pacman::addUpdateRect() {
	Screen::getInstance()->AddUpdateRects(least(x,last_x), least(y,last_y), pacman_sf->w + abs(x-last_x), pacman_sf->h + abs(y-last_y));
}

void Pacman::drawLives() {
	const int X_OFFSET = pacman_links_1->w + Constants::LIVES_DISTANCE;
	for (int i = 0; i < remainingLives-1; ++i)
		Screen::getInstance()->draw(pacman_links_1, Constants::LIVES_X+(i*X_OFFSET), Constants::LIVES_Y);
	Screen::getInstance()->AddUpdateRects(Constants::LIVES_X, Constants::LIVES_Y, (remainingLives*X_OFFSET)+pacman_links_1->w, pacman_links_1->h);
}

void Pacman::addLives(int num) {
	remainingLives += num;
}

int Pacman::getRemainingLives() {
	return remainingLives;
}

void Pacman::setRemainingLives(int lives) {
	remainingLives = lives;
}

