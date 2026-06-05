#include "rail.h"

Rail::Rail(int init_x1, int init_y1, int init_x2, int init_y2) {
	x1 = init_x1;
	y1 = init_y1;
	x2 = init_x2;
	y2 = init_y2;
	for (int i=0; i<12; i++)
		idxPills[i] = -1;
	numPills = 0;
}

Rail::~Rail() {
}
