#include "funny_animation.h"

FunnyAnimation* FunnyAnimation::instance = NULL;

FunnyAnimation::FunnyAnimation():
	screen(Screen::getInstance()),
	pacman(Pacman::getInstance()),
	ghosts(Ghost::getGhostArray()),
	labyrinth(Labyrinth::getInstance()){
		animScore200  = Screen::getTextSurface(Screen::getSmallFont(), "200",    Constants::WHITE_COLOR);
		animScore400  = Screen::getTextSurface(Screen::getSmallFont(), "400",    Constants::WHITE_COLOR);
		animScore800  = Screen::getTextSurface(Screen::getSmallFont(), "800",    Constants::WHITE_COLOR);
		animScore1600 = Screen::getTextSurface(Screen::getSmallFont(), "1600",   Constants::WHITE_COLOR);
		pacmanName    = Screen::getTextSurface(Screen::getLargeFont(), "Pacman", Constants::YELLOW_COLOR);
		blinkyName    = Screen::getTextSurface(Screen::getLargeFont(), "Blinky", Constants::BLINKY_COLOR);
		pinkyName     = Screen::getTextSurface(Screen::getLargeFont(), "Pinky",  Constants::PINKY_COLOR);
		inkyName      = Screen::getTextSurface(Screen::getLargeFont(), "Inky",   Constants::INKY_COLOR);
		clydeName     = Screen::getTextSurface(Screen::getLargeFont(), "Clyde",  Constants::CLYDE_COLOR);
		animFruits    = new SDL_Surface*[NUM_FRUITS];
		animScores    = new SDL_Surface*[NUM_FRUITS];
		const char* fruits[NUM_FRUITS][2] = {{"gfx/cherry.png",     "100"},
											 {"gfx/strawberry.png", "300"},
											 {"gfx/orange.png",     "500"},
											 {"gfx/apple.png",      "700"},
											 {"gfx/grapes.png",    "1000"},
											 {"gfx/banana.png",    "2000"},
											 {"gfx/pear.png",      "3000"},
											 {"gfx/key.png",       "5000"}};
		for(int i = 0; i < NUM_FRUITS; ++i) {
			animFruits[i] = Screen::loadImage(fruits[i][0], 255);
			animScores[i] = Screen::getTextSurface(Screen::getSmallFont(), fruits[i][1], Constants::WHITE_COLOR);
		}

		animRect.x = 0;
		animRect.y = 200;
		animRect.w = 640;
		animRect.h = 23;
		for (int i = 0; i < NUM_FRUITS; i++) {
			xFruits[i]   = 460 - i*50;
			timeScore[i] = 0;
		}
		animation_counter = 0;
		timeScore200 = 0;
		timeScore400 = 0;
		timeScore800 = 0;
		timeScore1600 = 0;
		xScore200 = 0;
		xScore400 = 0;
		xScore800 = 0;
		xScore1600 = 0;
		xTarget = 0;
		idxAnimation = 0;
		animationPart = 0;
		animationTime = 0;
		lastAnimTime = 0;
		animWaitUntil = 0;
}

FunnyAnimation::~FunnyAnimation() {
	SDL_FreeSurface(animScore200);
	SDL_FreeSurface(animScore400);
	SDL_FreeSurface(animScore800);
	SDL_FreeSurface(animScore1600);
	SDL_FreeSurface(pacmanName);
	SDL_FreeSurface(blinkyName);
	SDL_FreeSurface(inkyName);
	SDL_FreeSurface(clydeName);
	for (int i = 0; i < NUM_FRUITS; i++) {
		SDL_FreeSurface(animFruits[i]);
		SDL_FreeSurface(animScores[i]);
	}
	delete[] animFruits;
}

FunnyAnimation* FunnyAnimation::getInstance() {
	if(!instance)
		instance = new FunnyAnimation();
	return instance;
}

void FunnyAnimation::cleanUpInstance() {
	if(instance) {
		delete(instance);
		instance = NULL;
	}
}

void FunnyAnimation::animate() {
	lastAnimTime = animationTime;
	animationTime += MIN_FRAME_DURATION;
	if (idxAnimation == 0) {
		// Animation 1: Pacman comes from the right and leaves to the left.
		if (animationTime >= ANIMATION_WAIT) {
			if (lastAnimTime < ANIMATION_WAIT) {
				animWaitUntil = 0;
				pacman->reset();
				pacman->set_position(640, 200);
			}
			pacman->move_left(MIN_FRAME_DURATION, -23);
			if (pacman->x <= -23) {
				idxAnimation  = (idxAnimation + 1) % NUM_ANIMATIONS;
				animationTime = 0;
				animationPart = 0;
				screen->AddUpdateRects(animRect.x, animRect.y, animRect.w, animRect.h);
			}
			screen->fillRect(&animRect, 0, 0, 0);
			pacman->animate();
			pacman->draw();
			pacman->addUpdateRect();
			screen->clearOutsideClipRect();
			screen->Refresh();
		}

	} else if (idxAnimation == 1) {
		// Animation 2: Pacman comes from the left, followed by blinky, pinky, inky and clyde.
		//              Pacman eats the superpill on the right, turns around and eats each ghost.
		if (animationTime >= ANIMATION_WAIT) {
			if (lastAnimTime < ANIMATION_WAIT) {
				animationPart = 1;
				animWaitUntil = 0;
				// initialize figures
				pacman->reset();
				pacman->set_position(-23, 200);
				for(int i = 0; i < 4; ++i) {
					ghosts[i]->reset();
					ghosts[i]->set_position(-60 - (i*30), 200);
				}
				animation_counter = 0;
			}
			if (animationPart == 1) {
				pacman->move_right(MIN_FRAME_DURATION, 540);
				if (pacman->x >= 540) {
					animationPart = 2;
					ghosts[0]->set_hunter(Figur::PACMAN);
					ghosts[1]->set_hunter(Figur::PACMAN);
					ghosts[2]->set_hunter(Figur::PACMAN);
					ghosts[3]->set_hunter(Figur::PACMAN);
				}
				ghosts[0]->move_right(MIN_FRAME_DURATION, 640);
				ghosts[1]->move_right(MIN_FRAME_DURATION, 640);
				ghosts[2]->move_right(MIN_FRAME_DURATION, 640);
				ghosts[3]->move_right(MIN_FRAME_DURATION, 640);
				animation_counter += MIN_FRAME_DURATION;
			} else if (animationPart == 2) {
				if (animationTime >= animWaitUntil) {
					pacman->move_left(MIN_FRAME_DURATION, -23);
					pacman->setVisibility(true);
					if (pacman->x <= -23) {
						idxAnimation  = (idxAnimation + 1) % NUM_ANIMATIONS;
						animationTime = 0;
						animationPart = 0;
						timeScore200  = 0;
						timeScore400  = 0;
						timeScore800  = 0;
						timeScore1600 = 0;
						screen->AddUpdateRects(animRect.x, animRect.y, animRect.w, animRect.h);
					}
					ghosts[0]->move_left(MIN_FRAME_DURATION, -23);
					ghosts[1]->move_left(MIN_FRAME_DURATION, -23);
					ghosts[2]->move_left(MIN_FRAME_DURATION, -23);
					ghosts[3]->move_left(MIN_FRAME_DURATION, -23);
				}
				if (pacman->x <= ghosts[0]->x + 11 && ghosts[0]->isVisible()) {
					ghosts[0]->setVisibility(false);
					xScore200 = ghosts[0]->x;
					timeScore200 = 400;
					pacman->setVisibility(false);
					animWaitUntil = animationTime + 400;
				}
				if (pacman->x <= ghosts[1]->x + 11 && ghosts[1]->isVisible()) {
					ghosts[1]->setVisibility(false);
					xScore400 = ghosts[1]->x;
					timeScore400 = 400;
					pacman->setVisibility(false);
					animWaitUntil = animationTime + 400;
				}
				if (pacman->x <= ghosts[2]->x + 11 && ghosts[2]->isVisible()) {
					ghosts[2]->setVisibility(false);
					xScore800 = ghosts[2]->x;
					timeScore800 = 400;
					pacman->setVisibility(false);
					animWaitUntil = animationTime + 400;
				}
				if (pacman->x <= ghosts[3]->x + 11 && ghosts[3]->isVisible()) {
					ghosts[3]->setVisibility(false);
					xScore1600 = ghosts[3]->x;
					timeScore1600 = 400;
					pacman->setVisibility(false);
					animWaitUntil = animationTime + 400;
				}
				animation_counter += MIN_FRAME_DURATION;
			}
			screen->fillRect(&animRect, 0, 0, 0);
			if (animation_counter > 100) {
				animation_counter -= 100;
				ghosts[0]->animation();
				ghosts[1]->animation();
				ghosts[2]->animation();
				ghosts[3]->animation();
				labyrinth->pill_animation();
			}
			if (animationPart == 1) {
				// superpill not yet eaten
				screen->draw(labyrinth->get_superpill_sf(), 546, 206);
				screen->AddUpdateRects(546, 206, labyrinth->get_superpill_sf()->w, labyrinth->get_superpill_sf()->h);
			}
			ghosts[0]->draw();
			ghosts[0]->addUpdateRect();
			ghosts[1]->draw();
			ghosts[1]->addUpdateRect();
			ghosts[2]->draw();
			ghosts[2]->addUpdateRect();
			ghosts[3]->draw();
			ghosts[3]->addUpdateRect();
			pacman->animate();
			pacman->draw();
			pacman->addUpdateRect();
			if (timeScore200 > 0) {
				timeScore200 -= MIN_FRAME_DURATION;
				if (timeScore200 <= 0) {
					timeScore200 = 0;
				} else {
					screen->draw(animScore200, xScore200, 205);
				}
				screen->AddUpdateRects(xScore200, 205, animScore200->w, animScore200->h);
			}
			if (timeScore400 > 0) {
				timeScore400 -= MIN_FRAME_DURATION;
				if (timeScore400 <= 0) {
					timeScore400 = 0;
				} else {
					screen->draw(animScore400, xScore400, 205);
				}
				screen->AddUpdateRects(xScore400, 205, animScore400->w, animScore400->h);
			}
			if (timeScore800 > 0) {
				timeScore800 -= MIN_FRAME_DURATION;
				if (timeScore800 <= 0) {
					timeScore800 = 0;
				} else {
					screen->draw(animScore800, xScore800, 205);
				}
				screen->AddUpdateRects(xScore800, 205, animScore800->w, animScore800->h);
			}
			if (timeScore1600 > 0) {
				timeScore1600 -= MIN_FRAME_DURATION;
				if (timeScore1600 <= 0) {
					timeScore1600 = 0;
				} else {
					screen->draw(animScore1600, xScore1600, 205);
				}
				screen->AddUpdateRects(xScore1600, 205, animScore1600->w, animScore1600->h);
			}
			screen->clearOutsideClipRect();
			screen->Refresh();
		}
	}else if (idxAnimation == 2) {
		// Animation 3: Pacman comes from the left, stops in the middle, name "Pacman" shows up for a while, Pacman leaves to the right.
		//              Blinky from right to left, Pinky from left to right, Inky from right to left, Clyde from left to right.
		if (animationTime >= ANIMATION_WAIT) {
			if (lastAnimTime < ANIMATION_WAIT) {
				animationPart = 1;
				animWaitUntil = 0;
				// initialize figures
				pacman->reset();
				pacman->set_position(-23, 200);
				ghosts[0]->reset();
				ghosts[0]->set_position(640, 200);
				ghosts[1]->reset();
				ghosts[1]->set_position(-23, 200);
				ghosts[2]->reset();
				ghosts[2]->set_position(640, 200);
				ghosts[3]->reset();
				ghosts[3]->set_position(-23, 200);
				animation_counter = 0;
			}
			screen->fillRect(&animRect, 0, 0, 0);
			if (animationPart == 1) {
				xTarget = 320 + (pacmanName->w >> 1) + 50;
				pacman->move_right(MIN_FRAME_DURATION, xTarget);
				if (pacman->x >= xTarget) {
					pacman->right_pic(0);  // mouth open
					animRectTmp.x = (short int) (xTarget - 50 - pacmanName->w);
					animRectTmp.y = (short int) (223-pacmanName->h);
					animRectTmp.w = (short int) pacmanName->w;
					animRectTmp.h = (short int) pacmanName->h;
					screen->draw(pacmanName, animRectTmp.x, animRectTmp.y);
					screen->AddUpdateRects(animRectTmp.x, animRectTmp.y, animRectTmp.w, animRectTmp.h);
					animationPart = 2;
					animWaitUntil = animationTime + 2000;
				}
			} else if (animationPart == 2) {
				if (animationTime >= animWaitUntil) {
					screen->fillRect(&animRectTmp, 0, 0, 0);
					screen->AddUpdateRects(animRectTmp.x, animRectTmp.y, animRectTmp.w, animRectTmp.h);
					animationPart = 3;
				} else {
					screen->draw(pacmanName, animRectTmp.x, animRectTmp.y);
					screen->AddUpdateRects(animRectTmp.x, animRectTmp.y, animRectTmp.w, animRectTmp.h);
				}
			} else if (animationPart == 3) {
				pacman->move_right(MIN_FRAME_DURATION, 690);
				if (pacman->x >= 690) {
					animationPart = 4;
				}
			} else if (animationPart == 4) {
				xTarget = 320 - (blinkyName->w >> 1) - 73;
				ghosts[0]->move_left(MIN_FRAME_DURATION, xTarget);
				if (ghosts[0]->x <= xTarget) {
					animRectTmp.x = (short int) (xTarget + 73);
					animRectTmp.y = (short int) (223-blinkyName->h);
					animRectTmp.w = (short int) blinkyName->w;
					animRectTmp.h = (short int) blinkyName->h;
					screen->draw(blinkyName, animRectTmp.x, animRectTmp.y);
					screen->AddUpdateRects(animRectTmp.x, animRectTmp.y, animRectTmp.w, animRectTmp.h);
					animationPart = 5;
					animWaitUntil = animationTime + 2000;
				}
			} else if (animationPart == 5) {
				if (animationTime >= animWaitUntil) {
					screen->fillRect(&animRectTmp, 0, 0, 0);
					screen->AddUpdateRects(animRectTmp.x, animRectTmp.y, animRectTmp.w, animRectTmp.h);
					animationPart = 6;
				} else {
					screen->draw(blinkyName, animRectTmp.x, animRectTmp.y);
					screen->AddUpdateRects(animRectTmp.x, animRectTmp.y, animRectTmp.w, animRectTmp.h);
				}
			} else if (animationPart == 6) {
				ghosts[0]->move_left(MIN_FRAME_DURATION, -73);
				if (ghosts[0]->x <= -73) {
					animationPart = 7;
				}
			} else if (animationPart == 7) {
				xTarget = 320 + (pinkyName->w >> 1) + 50;
				ghosts[1]->move_right(MIN_FRAME_DURATION, xTarget);
				if (ghosts[1]->x >= xTarget) {
					animRectTmp.x = (short int) (xTarget - 50 - pinkyName->w);
					animRectTmp.y = (short int) (223-pinkyName->h);
					animRectTmp.w = (short int) pinkyName->w;
					animRectTmp.h = (short int) pinkyName->h;
					screen->draw(pinkyName, animRectTmp.x, animRectTmp.y);
					screen->AddUpdateRects(animRectTmp.x, animRectTmp.y, animRectTmp.w, animRectTmp.h);
					animationPart = 8;
					animWaitUntil = animationTime + 2000;
				}
			} else if (animationPart == 8) {
				if (animationTime >= animWaitUntil) {
					screen->fillRect(&animRectTmp, 0, 0, 0);
					screen->AddUpdateRects(animRectTmp.x, animRectTmp.y, animRectTmp.w, animRectTmp.h);
					animationPart = 9;
				} else {
					screen->draw(pinkyName, animRectTmp.x, animRectTmp.y);
					screen->AddUpdateRects(animRectTmp.x, animRectTmp.y, animRectTmp.w, animRectTmp.h);
				}
			} else if (animationPart == 9) {
				ghosts[1]->move_right(MIN_FRAME_DURATION, 690);
				if (ghosts[1]->x >= 690) {
					animationPart = 10;
				}
			} else if (animationPart == 10) {
				xTarget = 320 - (inkyName->w >> 1) - 73;
				ghosts[2]->move_left(MIN_FRAME_DURATION, xTarget);
				if (ghosts[2]->x <= xTarget) {
					animRectTmp.x = (short int) (xTarget + 73);
					animRectTmp.y = (short int) (223-inkyName->h);
					animRectTmp.w = (short int) inkyName->w;
					animRectTmp.h = (short int) inkyName->h;
					screen->draw(inkyName, animRectTmp.x, animRectTmp.y);
					screen->AddUpdateRects(animRectTmp.x, animRectTmp.y, animRectTmp.w, animRectTmp.h);
					animationPart = 11;
					animWaitUntil = animationTime + 2000;
				}
			} else if (animationPart == 11) {
				if (animationTime >= animWaitUntil) {
					screen->fillRect(&animRectTmp, 0, 0, 0);
					screen->AddUpdateRects(animRectTmp.x, animRectTmp.y, animRectTmp.w, animRectTmp.h);
					animationPart = 12;
				} else {
					screen->draw(inkyName, animRectTmp.x, animRectTmp.y);
					screen->AddUpdateRects(animRectTmp.x, animRectTmp.y, animRectTmp.w, animRectTmp.h);
				}
			} else if (animationPart == 12) {
				ghosts[2]->move_left(MIN_FRAME_DURATION, -73);
				if (ghosts[2]->x <= -73) {
					animationPart = 13;
				}
			} else if (animationPart == 13) {
				xTarget = 320 + (clydeName->w >> 1) + 50;
				ghosts[3]->move_right(MIN_FRAME_DURATION, xTarget);
				if (ghosts[3]->x >= xTarget) {
					animRectTmp.x = (short int) (xTarget - 50 - clydeName->w);
					animRectTmp.y = (short int) (223-clydeName->h);
					animRectTmp.w = (short int) clydeName->w;
					animRectTmp.h = (short int) clydeName->h;
					screen->draw(clydeName, animRectTmp.x, animRectTmp.y);
					screen->AddUpdateRects(animRectTmp.x, animRectTmp.y, animRectTmp.w, animRectTmp.h);
					animationPart = 14;
					animWaitUntil = animationTime + 2000;
				}
			} else if (animationPart == 14) {
				if (animationTime >= animWaitUntil) {
					screen->fillRect(&animRectTmp, 0, 0, 0);
					screen->AddUpdateRects(animRectTmp.x, animRectTmp.y, animRectTmp.w, animRectTmp.h);
					animationPart = 15;
				} else {
					screen->draw(clydeName, animRectTmp.x, animRectTmp.y);
					screen->AddUpdateRects(animRectTmp.x, animRectTmp.y, animRectTmp.w, animRectTmp.h);
				}
			} else if (animationPart == 15) {
				ghosts[3]->move_right(MIN_FRAME_DURATION, 690);
				if (ghosts[3]->x >= 690) {
					idxAnimation  = (idxAnimation + 1) % NUM_ANIMATIONS;
					animationTime = 0;
					animationPart = 0;
					screen->AddUpdateRects(animRect.x, animRect.y, animRect.w, animRect.h);
				}
			}
			if (1 <= animationPart && animationPart <= 3) {
				pacman->animate();
				pacman->draw();
				pacman->addUpdateRect();
			}
			if (4 <= animationPart && animationPart <= 15) {
				animation_counter += MIN_FRAME_DURATION;
				if (animation_counter > 100) {
					animation_counter -= 100;
					ghosts[0]->animation();
					ghosts[1]->animation();
					ghosts[2]->animation();
					ghosts[3]->animation();
				}
				if (4 <= animationPart && animationPart <= 6) {
					ghosts[0]->draw();
					ghosts[0]->addUpdateRect();
				} else if (7 <= animationPart && animationPart <= 9) {
					ghosts[1]->draw();
					ghosts[1]->addUpdateRect();
				} else if (10 <= animationPart && animationPart <= 12) {
					ghosts[2]->draw();
					ghosts[2]->addUpdateRect();
				} else if (13 <= animationPart && animationPart <= 15) {
					ghosts[3]->draw();
					ghosts[3]->addUpdateRect();
				}
			}
			screen->clearOutsideClipRect();
			screen->Refresh();
		}
	} else if (idxAnimation == 3) {
		// Animation 4: Pacman comes from the right eating all bonus fruits.
		if (animationTime >= ANIMATION_WAIT) {
			if (lastAnimTime < ANIMATION_WAIT) {
				animationPart = 0;
				animWaitUntil = 0;
				pacman->reset();
				pacman->set_position(840, 200);
			}
			screen->fillRect(&animRect, 0, 0, 0);
			if (animationTime >= animWaitUntil) {
				pacman->move_left(MIN_FRAME_DURATION, -23);
				pacman->setVisibility(true);
			}
			for (int i = animationPart; i < NUM_FRUITS; i++) {
				if (pacman->x < xFruits[i]+11 && animationPart < i+1) {
					animationPart = i+1;  // here, means "fruit No. i eaten"
					screen->AddUpdateRects(xFruits[i], 200, animFruits[i]->w, animFruits[i]->h);
					timeScore[i] = 400;
					pacman->setVisibility(false);
					animWaitUntil = animationTime + 400;
					break;
				}
			}
			for (int i = animationPart; i < NUM_FRUITS; i++) {
				screen->draw(animFruits[i], xFruits[i], 200);
				screen->AddUpdateRects(xFruits[i], 200, animFruits[i]->w, animFruits[i]->h);
			}
			if (pacman->x <= -23) {
				idxAnimation  = (idxAnimation + 1) % NUM_ANIMATIONS;
				animationTime = 0;
				animationPart = 0;
				for (int i = 0; i < NUM_FRUITS; i++) {
					timeScore[i] = 0;
				}
				screen->AddUpdateRects(animRect.x, animRect.y, animRect.w, animRect.h);
			}
			pacman->animate();
			pacman->draw();
			pacman->addUpdateRect();
			for (int i = 0; i < NUM_FRUITS; i++) {
				if (timeScore[i] > 0) {
					timeScore[i] -= MIN_FRAME_DURATION;
					if (timeScore[i] <= 0) {
						timeScore[i] = 0;
					} else {
						screen->draw(animScores[i], xFruits[i], 205);
					}
					screen->AddUpdateRects(xFruits[i], 205, animScores[i]->w, animScores[i]->h);
				}
			}
			screen->clearOutsideClipRect();
			screen->Refresh();
		}
	}else if (idxAnimation == 4) {
		// Animation 5: Pacman comes from the left, followed by Blinky, Inky and Clyde. But Pinky
		//              comes from the right, and moves beyond the superpill which Pacman thus cannot
		//              reach anymore. Pacman changes his direction twice, runs into Pinky, and dies.
		//              The ghosts disappear after Pacman died.
		if (animationTime >= ANIMATION_WAIT) {
			if (lastAnimTime < ANIMATION_WAIT) {
				animationPart = 1;
				animWaitUntil = 0;
				// initialize figures
				pacman->reset();
				pacman->set_position(-23, 200);
				ghosts[0]->reset();
				ghosts[0]->set_position(-120, 200);
				ghosts[1]->reset();
				ghosts[1]->set_position(980, 200);
				ghosts[2]->reset();
				ghosts[2]->set_position(-150, 200);
				ghosts[3]->reset();
				ghosts[3]->set_position(-210, 200);
				animation_counter = 0;
			}
			if (animationPart == 1) {
				pacman->move_right(MIN_FRAME_DURATION, 540);
				ghosts[0]->move_right(MIN_FRAME_DURATION, 640);
				ghosts[1]->move_left(MIN_FRAME_DURATION, -23);
				ghosts[2]->move_right(MIN_FRAME_DURATION, 640);
				ghosts[3]->move_right(MIN_FRAME_DURATION, 640);
				if (pacman->x >= ghosts[1]->x - 60) {
					animationPart = 2;
				}
			} else if (animationPart == 2) {
				pacman->move_left(MIN_FRAME_DURATION, -23);
				ghosts[0]->move_right(MIN_FRAME_DURATION, 640);
				ghosts[1]->move_left(MIN_FRAME_DURATION, -23);
				ghosts[2]->move_right(MIN_FRAME_DURATION, 640);
				ghosts[3]->move_right(MIN_FRAME_DURATION, 640);
				if (pacman->x <= ghosts[0]->x + 35) {
					animationPart = 3;
				}
			} else if (animationPart == 3) {
				pacman->move_right(MIN_FRAME_DURATION, 540);
				ghosts[0]->move_right(MIN_FRAME_DURATION, 640);
				ghosts[1]->move_left(MIN_FRAME_DURATION, -23);
				ghosts[2]->move_right(MIN_FRAME_DURATION, 640);
				ghosts[3]->move_right(MIN_FRAME_DURATION, 640);
				if (pacman->x >= ghosts[1]->x - 11) {
					pacman->right_pic(0);  // mouth open
					pacman->set_dying(10);
					animationPart = 4;
				}
			} else if (animationPart == 4) {
				if (animation_counter < MIN_FRAME_DURATION && !pacman->die_animation(/*skipSound=*/true)) {
					pacman->setVisibility(false);
					animationPart = 5;
					animWaitUntil = animationTime + 2000;
				}
			} else if (animationPart == 5) {
				if (animationTime >= animWaitUntil) {
					idxAnimation  = (idxAnimation + 1) % NUM_ANIMATIONS;
					animationTime = 0;
					animationPart = 0;
					screen->AddUpdateRects(animRect.x, animRect.y, animRect.w, animRect.h);
				}
			}
			screen->fillRect(&animRect, 0, 0, 0);
			animation_counter += MIN_FRAME_DURATION;
			if (animation_counter > 100) {
				animation_counter -= 100;
				ghosts[0]->animation();
				ghosts[1]->animation();
				ghosts[2]->animation();
				ghosts[3]->animation();
				labyrinth->pill_animation();
			}
			if (idxAnimation == 4) {
				screen->draw(labyrinth->get_superpill_sf(), 546, 206);
				screen->AddUpdateRects(546, 206, labyrinth->get_superpill_sf()->w, labyrinth->get_superpill_sf()->h);
				ghosts[0]->draw();
				ghosts[0]->addUpdateRect();
				ghosts[1]->draw();
				ghosts[1]->addUpdateRect();
				ghosts[2]->draw();
				ghosts[2]->addUpdateRect();
				ghosts[3]->draw();
				ghosts[3]->addUpdateRect();
				if (animationPart < 4) {
					pacman->animate();
				}
				pacman->draw();
				pacman->addUpdateRect();
			}
			screen->clearOutsideClipRect();
			screen->Refresh();
		}
	}//Ende Animation 3
}
