#include "figur.h"
#include "math.h"


Figur::Figur(int init_x, int init_y, int init_v):
	initial_x(init_x),
	initial_y(init_y),
	initial_v(init_v),
	visible(true),
	directionChanged(false)
{
	x = init_x;
	y = init_y;
	last_x = init_x;
	last_y = init_y;
	cur_x = init_x << 10;
	cur_y = init_y << 10;
	speed = init_v;
}

Figur::~Figur() {
}

void Figur::move_left(int ms, int stop_at) {
	last_x = x;
	last_y = y;
	cur_x = greatest(cur_x - speed*ms, stop_at << 10);
	x = cur_x >> 10;
	directionChanged = (direction != LEFT);
	direction = LEFT;
}

void Figur::move_up(int ms, int stop_at) {
	last_x = x;
	last_y = y;
	cur_y = greatest(cur_y - speed*ms, stop_at << 10);
	y = cur_y >> 10;
	directionChanged = (direction != UP);
	direction = UP;
}

void Figur::move_right(int ms, int stop_at) {
	last_x = x;
	last_y = y;
	cur_x = least(cur_x + speed*ms, stop_at << 10);
	x = cur_x >> 10;
	directionChanged = (direction != RIGHT);
	direction = RIGHT;
}

void Figur::move_down(int ms, int stop_at) {
	last_x = x;
	last_y = y;
	cur_y = least(cur_y + speed*ms, stop_at << 10);
	y = cur_y >> 10;
	directionChanged = (direction != DOWN);
	direction = DOWN;
}

void Figur::move_dir(int ms, Direction direction) {
	if(direction == LEFT)
		move_left(ms);
	if(direction == UP)
		move_up(ms);
	if(direction == RIGHT)
		move_right(ms);
	if(direction == DOWN)
		move_down(ms);
}
void Figur::set_speed(int v) {
	speed = v;
}

int Figur::get_speed() const {
	return speed;
}

bool Figur::was_moving() {
	if((x != last_x) || (y != last_y))
		return true;
	else
		return false;
}

void Figur::parking() {
	last_x = x;
	last_y = y;
}

Figur::Direction Figur::get_direction() const {
	return direction;
}

void Figur::set_direction(Direction direction) {
	this->direction = direction;
}

void Figur::set_position(int new_x, int new_y) {
	last_x = x;
	last_y = y;
	x = new_x;
	y = new_y;
	cur_x = new_x << 10;
	cur_y = new_y << 10;
}

int Figur::least(int a, int b) {
	return (a < b) ? a : b;
}

int Figur::greatest(int a, int b) {
	return (a > b) ? a : b;
}

void Figur::reset() {
}

Figur::Hunter Figur::get_hunter() const {
	return NONE;
}

void Figur::set_hunter(Hunter hunter) {
	this->hunter = hunter;
}

void Figur::setVisibility(bool v) {
	int prev_value = this->visible;
	this->visible = (v == false) ? false : true;
	if (prev_value != this->visible) {
		draw();
	}
	addUpdateRect();
}

bool Figur::isVisible() {
	return visible;
}
