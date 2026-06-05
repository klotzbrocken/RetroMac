#ifndef SOUNDS_H
#define SOUNDS_H
#include <SDL2/SDL.h>
#include <SDL2/SDL_mixer.h>
#include <iostream>
#include "cmdline_options.h"
#include "platform.h"
#include "labyrinth_observer.h"

#define SAFE_FREE_CHUNK(x) if(x){Mix_FreeChunk(x);x=0;}
#define SAFE_FREE_MUSIC(x) if(x){Mix_FreeMusic(x);x=0;}

class Sounds : public LabyrinthObserver {
	public:
		static Sounds *getInstance();
		static void cleanUpInstance();
		bool isEnabled() const;
		bool isMusicEnabled() const;
		void setEnabled(bool newValue = true);
		void setMusicEnabled(bool newValue = true);
		void toggleEnabled();
		void toggleMusicEnabled();
		enum MusicType {NONE, INTRO, NORMAL, SUPERPILL, GHOST_EATEN};
		enum SingleSounds {DYING, EXTRA_MAN, FRUIT, EAT_GHOST};
		void pauseAll();
		void resumeAll();
		void playMunch();
		void playIntro();
		void stopMusic();
		void stopChannels();
		void playSingleSound(SingleSounds singlesounds);
		void playNormalMusic();
		void playSuperpillMusic();
		void playGhostEatenMusic();
		Mix_Chunk *loadWaveSound(const char *filename);
		Mix_Music *loadWaveMusic(const char *filename);
	private:
		static Sounds *instance;
		Sounds();
		~Sounds();
		void initialize();
		MusicType musicPlaying;
		bool enabled;
		bool musicEnabled;
		bool initialized;
		bool audioAvailable;
		Mix_Chunk *chunk_munch_a = NULL;
		Mix_Chunk *chunk_munch_b = NULL;
		int channel_munch;
		bool munch_toggle;
		Mix_Music *music_intro = NULL;
		Mix_Music *music_siren_slow = NULL;
		Mix_Music *music_siren_medium = NULL;
		Mix_Music *music_siren_fast = NULL;
		Mix_Music *music_superpill_loop = NULL;
		Mix_Music *music_eat_ghost = NULL;
		Mix_Chunk *chunk_dying = NULL;
		Mix_Chunk *chunk_extra_man = NULL;
		Mix_Chunk *chunk_fruit = NULL;
		Mix_Chunk *chunk_eat_ghost = NULL;
		void setPanicMode(int set);
		int panicMode;
};

#endif
