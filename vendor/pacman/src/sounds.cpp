#include "sounds.h"
#include "labyrinth.h"

Sounds *Sounds::instance = NULL;

Sounds *Sounds::getInstance() {
	if (!instance) {
		instance = new Sounds();
	}
	return instance;
}

void Sounds::cleanUpInstance() {
	if (instance) {
		delete instance;
		instance = NULL;
	}
}

Sounds::Sounds():
	channel_munch(-1),
	munch_toggle(true),
	audioAvailable(true),
	enabled(!CommandLineOptions::exists("s","nosound")),
	musicEnabled(!CommandLineOptions::exists("m","nomusic")),
	initialized(false),
	musicPlaying(NONE),
	panicMode(false)
{
	if (enabled || musicEnabled) {
		initialize();
	}
}

void Sounds::initialize() {
	int audio_rate = 44100;
	Uint16 audio_format = AUDIO_S16SYS;
	int audio_channels = 2;
	int audio_buffers = 2048;

	if (SDL_InitSubSystem(SDL_INIT_AUDIO) != 0) {
		std::cout << "SDL audio initialization failed (SDL_InitSubSystem): " << SDL_GetError() << std::endl;
		audioAvailable = false;
	}

	if (audioAvailable && Mix_OpenAudio(audio_rate, audio_format, audio_channels, audio_buffers) != 0) {
		std::cerr << "Unable to initialize audio (MixOpenAudio): " << Mix_GetError() << std::endl;
		audioAvailable = false;
	}
	if (audioAvailable) {
		chunk_munch_a = loadWaveSound("sounds/munch_a.wav");
		chunk_munch_b = loadWaveSound("sounds/munch_b.wav");
		chunk_dying = loadWaveSound("sounds/death_1.wav");
		chunk_extra_man = loadWaveSound("sounds/extra_man.wav");
		chunk_fruit = loadWaveSound("sounds/fruit.wav");
		chunk_eat_ghost = loadWaveSound("sounds/ghost_eat_3.wav");
		music_intro = loadWaveMusic("sounds/intro.wav");
		music_siren_slow = loadWaveMusic("sounds/siren_slow.wav");
		music_siren_medium = loadWaveMusic("sounds/siren_medium.wav");
		music_siren_fast = loadWaveMusic("sounds/siren_fast.wav");
		music_superpill_loop = loadWaveMusic("sounds/large_pellet_loop.wav");
		music_eat_ghost = loadWaveMusic("sounds/ghost_eat_1.wav");
		initialized = true;
	} else {
		enabled      = false;
		musicEnabled = false;
	}
	Labyrinth::getInstance()->setLabyrinthObserver(this);
}

Sounds::~Sounds() {
	if (initialized) {
		Mix_HaltChannel(-1);
		Mix_HaltMusic();
		SAFE_FREE_CHUNK(chunk_munch_a);
		SAFE_FREE_CHUNK(chunk_munch_b);
		SAFE_FREE_CHUNK(chunk_extra_man);
		SAFE_FREE_CHUNK(chunk_dying);
		SAFE_FREE_CHUNK(chunk_fruit);
		SAFE_FREE_CHUNK(chunk_eat_ghost);
		SAFE_FREE_MUSIC(music_intro);
		SAFE_FREE_MUSIC(music_siren_slow);
		SAFE_FREE_MUSIC(music_superpill_loop);
		SAFE_FREE_MUSIC(music_eat_ghost);
		Mix_CloseAudio();
		SDL_QuitSubSystem(SDL_INIT_AUDIO);
	}
}

bool Sounds::isEnabled() const {
	return enabled;
}

bool Sounds::isMusicEnabled() const {
	return musicEnabled;
}

void Sounds::setEnabled(bool newValue) {
	if (newValue && !initialized) {
		initialize();
	}
	if (audioAvailable || !newValue) {
		enabled = newValue;
		if (!enabled && audioAvailable) {
			stopChannels();
		}
	} else {
		std::cerr << "Sound is not available, so it cannot be enabled. See error message above." << std::endl;
	}
}

void Sounds::setMusicEnabled(bool newValue) {
	if (newValue && !initialized) {
		initialize();
	}
	if (audioAvailable || !newValue) {
		musicEnabled = newValue;
		if (!musicEnabled && audioAvailable) {
			stopMusic();
		}
	} else {
		std::cerr << "Music is not available, so it cannot be enabled. See error message above." << std::endl;
	}
}

void Sounds::toggleEnabled() {
	setEnabled(!isEnabled());
}

void Sounds::toggleMusicEnabled() {
	setMusicEnabled(!isMusicEnabled());
}

void Sounds::playMunch() {
	if(enabled) {
		if (channel_munch != -1) {
			Mix_HaltChannel(channel_munch);
		}
		if(munch_toggle) {
			if (chunk_munch_a)
				channel_munch = Mix_PlayChannel(channel_munch, chunk_munch_a, 0);
		} else {
			if (chunk_munch_b)
				channel_munch = Mix_PlayChannel(channel_munch, chunk_munch_b, 0);
		}
		if(channel_munch == -1) {
			std::cerr << "Unable to play WAV file: " << Mix_GetError() << std::endl;
		}
		munch_toggle = !munch_toggle;
	}
}

void Sounds::playIntro() {
	if(musicEnabled && musicPlaying != INTRO && music_intro) {
		stopMusic();
		if(Mix_PlayMusic(music_intro,1) == -1)
			std::cerr << "Unable to play WAV file: " << Mix_GetError() << std::endl;
		musicPlaying = INTRO;
	}
}

void Sounds::playNormalMusic() {
	if (musicEnabled && musicPlaying != NORMAL && (music_siren_slow || music_siren_medium)) {
		stopMusic();
		if(Mix_PlayMusic(panicMode ? music_siren_medium :music_siren_slow,-1) == -1)
			std::cerr << "Unable to play WAV file: " << Mix_GetError() << std::endl;
		musicPlaying = NORMAL;
	}
}

void Sounds::playSuperpillMusic() {
	if (musicEnabled && musicPlaying != SUPERPILL && music_superpill_loop) {
		stopMusic();
		if((Mix_PlayMusic(music_superpill_loop, -1)) == -1)
			std::cerr << "Unable to play WAV file: " << Mix_GetError() << std::endl;
		musicPlaying = SUPERPILL;
	}
}

void Sounds::playGhostEatenMusic() {
	if (musicEnabled && musicPlaying != GHOST_EATEN && music_eat_ghost) {
		stopMusic();
		if((Mix_PlayMusic(music_eat_ghost, -1)) == -1)
			std::cerr << "Unable to play WAV file: " << Mix_GetError() << std::endl;
		musicPlaying = GHOST_EATEN;
	}
}

void Sounds::stopMusic() {
	if(Mix_PlayingMusic())
		Mix_HaltMusic();
	musicPlaying = NONE;
}

void Sounds::stopChannels() {
	Mix_HaltChannel(-1);
}
void Sounds::pauseAll() {
	if(!Mix_PausedMusic())
		Mix_PauseMusic();
	Mix_Pause(-1);
}

void Sounds::resumeAll() {
	if(musicEnabled && Mix_PausedMusic())
		Mix_ResumeMusic();
	if(enabled)
		Mix_Resume(-1);
}

void Sounds::playSingleSound(SingleSounds singlesounds) {
	int channel;
	if (enabled) {
		if(singlesounds == DYING && chunk_dying) {
			channel = Mix_PlayChannel(-1, chunk_dying, 0);
		} else if (singlesounds == EXTRA_MAN && chunk_extra_man) {
			channel = Mix_PlayChannel(-1, chunk_extra_man, 0);
		} else if(singlesounds == FRUIT && chunk_fruit) {
			channel = Mix_PlayChannel(-1, chunk_fruit, 0);
		} else if(singlesounds == EAT_GHOST && chunk_eat_ghost) {
			channel = Mix_PlayChannel(-1, chunk_eat_ghost, 0);
		} else {
			return;
		}
		if (channel == -1) {
			std::cerr << "Unable to play WAV file: " << Mix_GetError() << std::endl;
		}
	}
}

Mix_Chunk *Sounds::loadWaveSound(const char *filename) {
	char filePath[256];
	getFilePath(filePath, filename);
	Mix_Chunk *sound = Mix_LoadWAV(filePath);
	if (!sound) {
		std::cerr << "Unable to load wave sound file (" << filename << "): " << Mix_GetError() << std::endl;
	}
	return sound;
}

Mix_Music *Sounds::loadWaveMusic(const char *filename) {
	char filePath[256];
	getFilePath(filePath, filename);
	Mix_Music *music = Mix_LoadMUS(filePath);
	if (!music) {
		std::cerr << "Unable to load wave music file (" << filename << "): " << Mix_GetError() << std::endl;
	}
	return music;
}

void Sounds::setPanicMode(int set) {
	panicMode = set;
	if(panicMode) {
		musicPlaying = NONE;
		playNormalMusic();
	}
}
