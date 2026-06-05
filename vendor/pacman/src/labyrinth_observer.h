#ifndef LABYRINTH_OBSERVER_H
#define LABYRINTH_OBSERVER_H
class LabyrinthObserver {
	public:
		LabyrinthObserver(){};
		virtual ~LabyrinthObserver(){};
		virtual void setPanicMode(int set) = 0;
};
#endif
