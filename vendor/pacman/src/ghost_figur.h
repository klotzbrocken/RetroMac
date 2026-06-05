#ifndef GHOST_FIGUR_H
#define GHOST_FIGUR_H

#include "constants.h"
#include "game.h"
#include "labyrinth.h"
#include "figur.h"
#include "pacman_figur.h"
#include "rail.h"
#include <time.h>
#include "labyrinth_observer.h"

class Ghost : public Figur, public LabyrinthObserver {
	public:
		static Ghost **getGhostArray();
		static void cleanUpGhostArray();

		/* draw ghost */
		virtual void draw();

		// animate the ghost, i.e. switch to the next image of the animation array
		void animation();

		// defines the leader (reference for redrawing)
		void set_leader(bool leader);
		void set_leader();

		// overloaded move of class Figur
		void move_dir(int ms, int direction, int max_links = 999, int max_oben = 999, int max_rechts = 999, int max_unten = 999);
		void move(int ms);

		// has the leader moved?
		static int was_moving_leader;

		// Returns the direction that has to be taken to reach the given target point (e.g. pacman's current position).
		// The result is coded like this: 0 = left, 1 = up, 2 = right, 3 = down
		int direction_to_point(int target_x, int target_y);
		int alternative_direction_to_point(int target_x, int target_y);  // Returns an alternative direction. Use it, if the exact one is not available.

		// This is the A.I. of the ghosts: with a defined probability, they move to the direction where pacman is.
		int choose_direction(Direction * sammel_richtung, int richtung_pacman, int sammel_counter, int intelligence);

		// moves a ghost on the defined rails
		void move_on_rails(int ms, Rail **ar_s);

		// returns the intelligence of the ghost
		int get_intelligence() const;

		// reset the ghost
		void reset();

		// this function registers the ghosts' rectangle (last and current position) for redrawing
		virtual void addUpdateRect();

		// hunting or hunted
		Figur::Hunter get_hunter() const;
		void set_hunter(Hunter hunter);

		// Callback method when pacman has touched this ghost. Returns 1 if this was dangerous for
		// pacman, 0 otherwise.
		bool touched();

		// announce the end of the hunting mode by blinking
		void blink();

		/* Idents for the ghosts */
		enum Ghosts {BLINKY, PINKY, INKY, CLYDE};

		// return the surface
		SDL_Surface* get_Surface() const;

		// set ghost_array
		//void setGhostArray(Ghost **ghost_array);

		Ghosts getGhostIdent() const;
		
	protected:
		/* constructor and destructor */
		Ghost(int init_x, int init_y, int init_intelligence,
		      Direction init_direction, int init_up_down, int ghost_ident);
		virtual ~Ghost();

	private:
		static int numGhosts;                    // current number of ghosts
		bool its_leader;
		int up_down;
		Direction initial_direction;
		int initial_intelligence;
		int initial_up_down;
		int num_animation_frames;
		int idx_animation;
		int ghost_ident;
		SDL_Surface *ghost_sf;
		SDL_Surface *ghost_1, *ghost_2, *ar_ghost[4];
		SDL_Surface *augen_0, *augen_1, *augen_2, *augen_3;
		SDL_Surface *escape_1, *escape_2, *escape_white_1, *escape_white_2;
		int idxCurrentRail;
		static Ghost **ghostArray;
		void setPanicMode(int set);
		int panicMode;
};

class Blinky : public Ghost {
	public:
		static Blinky *getInstance();
		static void cleanUpInstance();
	private:
		static Blinky *instance;
		Blinky();
		virtual ~Blinky() {}
};

class Pinky : public Ghost {
	public:
		static Pinky *getInstance();
		static void cleanUpInstance();
	private:
		static Pinky *instance;
		Pinky();
		virtual ~Pinky() {}
};

class Inky : public Ghost {
	public:
		static Inky *getInstance();
		static void cleanUpInstance();
	private:
		static Inky *instance;
		Inky();
		virtual ~Inky() {}
};

class Clyde : public Ghost {
	public:
		static Clyde *getInstance();
		static void cleanUpInstance();
	private:
		static Clyde *instance;
		Clyde();
		virtual ~Clyde() {}
};

#endif
