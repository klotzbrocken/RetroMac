#ifndef FIGUR_H
#define FIGUR_H
#include <SDL2/SDL.h>
#include <SDL2/SDL_image.h>
#include "platform.h"

class Figur {
	public:
		// constructor and destructor
		Figur(int init_x, int init_y, int init_v);
		virtual ~Figur();

		// direction
		enum Direction{LEFT, UP, RIGHT, DOWN};

		// position of the figure
		int x, y;

		// last x and y values (important when checking whether pills have been eaten)
		int last_x, last_y;

		// four directions of movement
		void move_left(int ms, int max_step = 999);
		void move_up(int ms, int max_step = 999);
		void move_right(int ms, int max_step = 999);
		void move_down(int ms, int max_step = 999);

		// wrapper for the directional movement functions
		void move_dir(int ms, Direction direction);

		// abstract draw method
		virtual void draw() = 0;

		// add an update rectangle to the screen
		virtual void addUpdateRect() = 0;

		// sets the speed of the figure
		void set_speed(int v);

		// returns the speed
		int get_speed() const;

		// has the figure moved? (needed for performance tuning)
		bool was_moving();

		// parking figur
		void parking();

		// returns the direction
		Direction get_direction() const;

		// sets the direction of movement
		void set_direction(Direction direction);

		// sets the position of the figure
		void set_position(int new_x, int new_y);

		// return the surface, must be implemented by subclasses
		virtual SDL_Surface* get_Surface() const = 0;  // makes the class abstract

		// reset the figure
		virtual void reset();

		// hunting or hunted
		enum Hunter {GHOST, PACMAN, NONE};
		virtual Hunter get_hunter() const;
		virtual void set_hunter(Hunter hunter);

		virtual bool touched() { return false; }

		//helper functions
		int least(int a, int b);
		int greatest(int a, int b);

		// sets the figure's visibility (e.g. for pacman after eating a ghost or a fruit)
		void setVisibility(bool v);

		// return the visibility
		bool isVisible();

	protected:
		int cur_y;
		int cur_x;
		int wechsel_x;
		int wechsel_y;
		int wechsel_rate;
		int speed;
		Direction direction;
		int intelligence;
		int initial_x;
		int initial_y;
		int initial_v;
		Hunter hunter;
		int visible;
		bool directionChanged;
};
#endif
