#include "game.h"
#include "level.h"
#include <iostream>

Game *Game::instance = NULL;

Game *Game::getInstance() {
	if (!instance) {
		instance = new Game();
	}
	return instance;
}

void Game::cleanUpInstance() {
	if (instance) {
		delete instance;
		instance = NULL;
	}
}

Game::Game():
	gameOver(false),
	stopMoving(false),
	refreshGhosts(false),
	pause(false),
	cnt_hunting_mode(-1),
	completeRedraw(false)
{
	scoreLabel = Screen::getTextSurface(Screen::getFont(), "Score", Constants::WHITE_COLOR);
	levelLabel = Screen::getTextSurface(Screen::getFont(), "Level", Constants::WHITE_COLOR);
}

Game::~Game() {
	if (scoreLabel) {
		SDL_FreeSurface(scoreLabel);
		scoreLabel = NULL;
	}
	if (levelLabel) {
		SDL_FreeSurface(levelLabel);
		levelLabel = NULL;
	}
}

void Game::init() {
	gameOver         = false;
	refreshGhosts    = false;
	stopMoving       = false;
	pause            = false;
	stopMoving       = true;
	animationCounter = 0;
	deltaT           = Constants::MIN_FRAME_DURATION;
	startOffset      = Constants::START_OFFSET;
	cnt_hunting_mode = -1;
	cnt_sleep        = -1;

	GameController::getInstance()->searchAndOpen();
	Labyrinth::getInstance()->resetLevel(1);

	// TODO: extract new class Player with a method reset()?
	Pacman::getInstance()->setRemainingLives(Constants::INITIAL_LIVES);
	Labyrinth::getInstance()->resetScore();
	Labyrinth::getInstance()->resetBonusStage();

	currentScore = Labyrinth::getInstance()->getScore();
	Screen::getInstance()->draw(scoreLabel, Constants::SCORE_X, Constants::SCORE_Y);
	Screen::getInstance()->draw(levelLabel, Constants::LEVEL_X, Constants::LEVEL_Y);
	Screen::getInstance()->addUpdateClipRect();
	Screen::getInstance()->Refresh();
	currentTicks     = SDL_GetTicks();
}

void Game::updateDelayTime() {
	// determine the correct game speed
	Uint32 lastTicks = currentTicks;
	currentTicks = SDL_GetTicks();
	deltaT = (int) (currentTicks - lastTicks);
	if (deltaT < Constants::MIN_FRAME_DURATION) {
		SDL_Delay(Constants::MIN_FRAME_DURATION - deltaT);
		deltaT = Constants::MIN_FRAME_DURATION;
		currentTicks = lastTicks + Constants::MIN_FRAME_DURATION;  // otherwise, the waiting time would cause problems within the next frame
	}
}

void Game::preselectDirection(int keycode, int value) {
	if (keycode == SDLK_LEFT || keycode == SDLK_h || keycode == SDL_CONTROLLER_BUTTON_DPAD_LEFT || ((keycode == SDL_CONTROLLER_AXIS_LEFTX) && (value < -Constants::AXIS_ACTIVE_ZONE))) {
		Pacman::getInstance()->direction_pre = Figur::LEFT;
	} else if (keycode == SDLK_UP || keycode == SDLK_k || keycode == SDL_CONTROLLER_BUTTON_DPAD_UP || ((keycode == SDL_CONTROLLER_AXIS_LEFTY) && (value < -Constants::AXIS_ACTIVE_ZONE))) {
		Pacman::getInstance()->direction_pre = Figur::UP;
	} else if (keycode == SDLK_RIGHT || keycode == SDLK_l || keycode == SDL_CONTROLLER_BUTTON_DPAD_RIGHT || ((keycode == SDL_CONTROLLER_AXIS_LEFTX) && (value > Constants::AXIS_ACTIVE_ZONE))) {
		Pacman::getInstance()->direction_pre = Figur::RIGHT;
	} else if (keycode == SDLK_DOWN || keycode == SDLK_j || keycode == SDL_CONTROLLER_BUTTON_DPAD_DOWN || ((keycode == SDL_CONTROLLER_AXIS_LEFTY) && (value > Constants::AXIS_ACTIVE_ZONE))) {
		Pacman::getInstance()->direction_pre = Figur::DOWN;
	}
}

void Game::togglePause() {
	pause = !pause;
	if(pause) {
		Sounds::getInstance()->pauseAll();
	} else {
		Sounds::getInstance()->resumeAll();
	}
}

bool Game::eventloop() {
	SDL_Event event;
	while(SDL_PollEvent(&event)) {
		switch(event.type) {
		case SDL_KEYDOWN:
			if(gameOver)
				return false;
			if(!Pacman::getInstance()->is_dying() && !pause) {
				preselectDirection(event.key.keysym.sym);
			}
			if(event.key.keysym.sym == SDLK_f) {
				Uint32 ticksBefore = SDL_GetTicks();
			    Screen::getInstance()->toggleFullscreen();
			    completeRedraw = true;
			    currentTicks += (SDL_GetTicks() - ticksBefore);
			} else if(event.key.keysym.sym == SDLK_s) {
				Sounds::getInstance()->toggleEnabled();
			} else if(event.key.keysym.sym == SDLK_m) {
				Sounds::getInstance()->toggleMusicEnabled();
				if (Sounds::getInstance()->isMusicEnabled()) {
					checkMusic();
				}
			} else if(event.key.keysym.sym == SDLK_p) {
				if(!Pacman::getInstance()->is_dying()) {
					togglePause();
				}
			} else if((event.key.keysym.sym == SDLK_q)||(event.key.keysym.sym == SDLK_ESCAPE)) {
				return false;
			}
			break;
		case SDL_CONTROLLERBUTTONDOWN:
			if(gameOver)
				return false;
			if(!Pacman::getInstance()->is_dying() && !pause) 
				preselectDirection(event.cbutton.button);
			if(event.cbutton.button == SDL_CONTROLLER_BUTTON_BACK) 
				return false;
			break;
		case SDL_CONTROLLERAXISMOTION:
			if(gameOver)
				return false;
			if(!Pacman::getInstance()->is_dying() && !pause)
				preselectDirection(event.caxis.axis, event.caxis.value);
			break;
		case SDL_QUIT:
			return false;
		}
		// Redraw, when overlapped by foreign window
		if(event.window.event == SDL_WINDOWEVENT_EXPOSED ||
		   event.window.event == SDL_WINDOWEVENT_FOCUS_GAINED) {
			Screen::getInstance()->clearOutsideClipRect();
			Screen::getInstance()->addTotalUpdateRect();
			Screen::getInstance()->Refresh();
		}
	}
	return true;
}

void Game::stop(bool stop) {
	stopMoving = stop;
	if(stop) {
		Sounds::getInstance()->stopMusic();
		Sounds::getInstance()->stopChannels();
	} else {
		checkMusic();
	}
}

void Game::setGameOver(bool gameOver) {
	this->gameOver = gameOver;
	if(gameOver) {
		stop(true);
		Labyrinth::getInstance()->setInitText("Game over", Constants::RED);
	}
	HighscoreList::getInstance()->load();
	if (!HighscoreList::getInstance()->isReadonly()) {
		HighscoreList::getInstance()->resetHighlightedEntry();
		HighscoreList::getInstance()->insertEntry(new HighscoreEntry(CommandLineOptions::getValue("","name"), Labyrinth::getInstance()->getScore(), Labyrinth::getInstance()->getLevelNumber()));
		//HighscoreList::getInstance()->print();  // for testing purposes
	}
}

void Game::startHuntingMode() {
	Labyrinth::getInstance()->resetBonusStage();
	if (cnt_hunting_mode < 0)
		cnt_hunting_mode = Level::getInstance()->getHuntingModeTime();
	else // hunting mode was still active - prolong the it's duration
		cnt_hunting_mode += Level::getInstance()->getHuntingModeTime();
	checkMusic();
}

void Game::stopHuntingMode() {
	cnt_hunting_mode = -1;
	Labyrinth::getInstance()->resetBonusStage();
	checkMusic();
}

void Game::sleep(int ms) {
	cnt_sleep = ms;
}

void Game::start() {
	init();
	Sounds::getInstance()->playIntro();
	// game loop
	while (eventloop()) {
		handleAnimations();

		// handle time based counters
		handleStartOffset();
		handleHuntingMode();
		handleSleep();
		handleFruit();

		// move all figures, if they are allowed to move - and check, what happened
		checkedMove();
		Pacman::getInstance()->check_eat_pills();
		checkScoreForExtraLife();
		checkedRedraw();
		if (checkLastPillEaten())
			continue;
		checkGhostTouched();

		updateDelayTime();
	}
	stop(true);
}

void Game::checkGameOver() {
	if (Pacman::getInstance()->getRemainingLives() <= 0) {
		setGameOver(true);
		startOffset = -1;  // do not start again
		Pacman::getInstance()->setVisibility(false);  // Pacman does not exist anymore
		for(int i = 0; i < Constants::TOTAL_NUM_GHOSTS; ++i)
			Ghost::getGhostArray()[i]->setVisibility(false);
	} else {
		Labyrinth::getInstance()->setInitText("Get Ready!");
		startOffset = Constants::START_OFFSET_2;
	}
}

void Game::handleAnimations() {
	animationCounter += deltaT;
	if(animationCounter > 100) {
		// ghost animations
		refreshGhosts = true;
		for(int i = 0; i < Constants::TOTAL_NUM_GHOSTS; ++i)
			Ghost::getGhostArray()[i]->animation();

		// Pacman die animation
		if(Pacman::getInstance()->is_dying()) {
			if(!Pacman::getInstance()->die_animation()) {
				stopHuntingMode();
				Labyrinth::getInstance()->resetAllFigures();
				Labyrinth::getInstance()->hideFruit();
				stop(true);
				Pacman::getInstance()->addLives(-1);
				checkGameOver();
				Screen::getInstance()->addUpdateClipRect();
			}
		}
		Labyrinth::getInstance()->pill_animation();
		animationCounter -= 100;
	} else {
		refreshGhosts = false;
	}
}

void Game::handleStartOffset() {
	// The "start offset" is a short wait time before the game begins, so the player may prepare to play.
	if(startOffset > 0) {
		startOffset -= deltaT;
		if (startOffset <= 0) {
			startOffset = -1;
			Labyrinth::getInstance()->hideInitText();
			stop(false);
		}
	}
}

void Game::handleHuntingMode() {
	// During the "hunting mode", ghosts can be eaten after eating a superpill, but only for a defined time.
	if(cnt_hunting_mode > 0 && !pause && cnt_sleep <= 0) {
		if (cnt_hunting_mode > 2000 && cnt_hunting_mode-deltaT <= 2000) {
			for(int i = 0; i < Constants::TOTAL_NUM_GHOSTS; ++i)
				Ghost::getGhostArray()[i]->blink();
		}
		cnt_hunting_mode -= deltaT;
		if (cnt_hunting_mode <= 0) {
			if (!Pacman::getInstance()->is_dying()) {
				for(int i = 0; i < Constants::TOTAL_NUM_GHOSTS; ++i) {
					if (Ghost::getGhostArray()[i]->get_hunter() != Figur::NONE)  // eaten ghosts still have to return to the castle
						Ghost::getGhostArray()[i]->set_hunter(Figur::GHOST);
				}
			}
			stopHuntingMode();
			checkMusic();
		}
	}
}

void Game::handleSleep() {
	// The "sleep counter" becomes active when the player got a special score (e.g. after eating a ghost or a fruit).
	if (cnt_sleep > 0 && !pause) {
		cnt_sleep -= deltaT;
		if (cnt_sleep <= 0) {
			cnt_sleep = 0;
			Labyrinth::getInstance()->hideSmallScore();
			Pacman::getInstance()->setVisibility(true);
			for(int i = 0; i < Constants::TOTAL_NUM_GHOSTS; ++i)
				Ghost::getGhostArray()[i]->setVisibility(true);
			checkMusic();
		}
	}
}

void Game::handleFruit() {
	// The fruit will only be displayed for a defined period. After that, it will disappear if it still has not been eaten.
	if (!pause && cnt_sleep <= 0) {
		Labyrinth::getInstance()->checkFruit(deltaT);
	}
}

bool Game::checkLastPillEaten() {
	if(Labyrinth::getInstance()->getNumRemainingPills() <= 0) {
		// init new level
		stop(true);
		stopHuntingMode();
		Labyrinth::getInstance()->nextLevel();
		startOffset = Constants::START_OFFSET;
		return true;
	}
	return false;
}

void Game::checkScoreForExtraLife() {
	int lastScore = currentScore;
	currentScore = Labyrinth::getInstance()->getScore();
	if ((lastScore<10000 && currentScore>=10000) || (lastScore<30000 && currentScore>=30000)) {
		Pacman::getInstance()->addLives(1);
		Sounds::getInstance()->playSingleSound(Sounds::EXTRA_MAN);
	}
}

void Game::checkedMove() {
	if (!pause && cnt_sleep <= 0 && !stopMoving) {
		Pacman::getInstance()->move(deltaT);
		for(int i = 0; i < Constants::TOTAL_NUM_GHOSTS; ++i)
			Ghost::getGhostArray()[i]->move(deltaT);
	}
}

void Game::checkedRedraw() {
	// redraw, if something has to be redrawn
	if (Ghost::was_moving_leader || refreshGhosts || completeRedraw) {
		// objects within the level
		Labyrinth::getInstance()->draw_pillen();  // including background
		Labyrinth::getInstance()->drawFruit();
		// figures
		Pacman::getInstance()->draw();
		Pacman::getInstance()->addUpdateRect();
		for(int i = 0; i < Constants::TOTAL_NUM_GHOSTS; ++i) {
			Ghost::getGhostArray()[i]->draw();
			Ghost::getGhostArray()[i]->addUpdateRect();
		}
		// topmost things within the level
		Labyrinth::getInstance()->draw_blocks();
		Labyrinth::getInstance()->drawSmallScore();
		Labyrinth::getInstance()->drawInitText();
		// information area: score, lives, the level's fruit
		Labyrinth::getInstance()->drawScoreValue();
		Screen::getInstance()->draw_dynamic_content(scoreLabel, Constants::SCORE_X, Constants::SCORE_Y);
		Labyrinth::getInstance()->drawLevelNumber();
		Screen::getInstance()->draw_dynamic_content(levelLabel, Constants::LEVEL_X, Constants::LEVEL_Y);
		Pacman::getInstance()->drawLives();
		Labyrinth::getInstance()->drawInfoFruits();
		if (completeRedraw) {
			completeRedraw = false;
			Screen::getInstance()->addTotalUpdateRect();
		}
		// bring it to the screen, really
		Screen::getInstance()->Refresh();
	}
}

void Game::checkGhostTouched() {
	if(Pacman::getInstance()->ghostTouched() && !Pacman::getInstance()->is_dying()) {
		stop(true);
		Pacman::getInstance()->set_dying(10);
	}
}

void Game::checkMusic() {
	if (pause || stopMoving || startOffset >= 1 || Pacman::getInstance()->is_dying()) {
		Sounds::getInstance()->stopMusic();
	} else if (cnt_hunting_mode <= 0) {
		Sounds::getInstance()->playNormalMusic();
	} else {
		int numBlue = 0, numNormal = 0, numEscaping = 0;
		for (int i = 0; i < Constants::TOTAL_NUM_GHOSTS; ++i) {
			if (Ghost::getGhostArray()[i]->get_hunter() == Figur::PACMAN) {
				++numBlue;
			} else if (Ghost::getGhostArray()[i]->get_hunter() == Figur::NONE) {
				++numEscaping;
			} else {
				++numNormal;
			}
		}
		if (numEscaping) {
			Sounds::getInstance()->playGhostEatenMusic();
		} else if (numBlue) {
			Sounds::getInstance()->playSuperpillMusic();
		} else {
			Sounds::getInstance()->playNormalMusic();
		}
	}
}

bool Game::isGameOver() {
	return gameOver;
}
