#include "platform.h"

#ifdef _WIN32
#define WINDOWS 1
#else
#define WINDOWS 0
#endif

#ifdef __APPLE__
#include <SDL2/SDL.h>
#endif

void getFilePath(char filePath[], const char file[]) {
     char installDir[512];
#if WINDOWS
         strcpy(installDir, "");
#elif defined(__APPLE__)
         // .app bundle: executable in Contents/MacOS, data in Contents/Resources/data.
         char *base = SDL_GetBasePath();   // ".../Contents/MacOS/"
         if (base) {
             snprintf(installDir, sizeof(installDir), "%s../Resources/data/", base);
             SDL_free(base);
         } else {
             strcpy(installDir, PACKAGE_DATA_DIR "/");
         }
#else
         strcpy(installDir, PACKAGE_DATA_DIR "/");
#endif
     strcpy(filePath, installDir);
     strcat(filePath, file);
}

static char gameDirBase[256];

void getGameDirPath(char filePath[], const char fileName[]) {
	if (!gameDirBase[0]) {
		if (WINDOWS) {
			char *env = getenv("APPDATA");
			if (env) {
				strcat(gameDirBase, env);
			} else {
				// not found, trying %HOMEDRIVE%%HOMEPATH%
				env = getenv("HOMEDRIVE");
				char *env2 = getenv("HOMEPATH");
				if (env && env2) {
					strcat(gameDirBase, env);
					strcat(gameDirBase, env2);
				} else {
					// not found, using current directory
				}
			}
			if (env) {
				size_t len = strlen(gameDirBase);
				if (len == 0 || gameDirBase[len-1] != '\\')
					strcat(gameDirBase, "\\");
				strcat(gameDirBase, "pacman_sdl\\");
			}
		} else {
			strcpy(gameDirBase, getenv("HOME"));
			size_t len = strlen(gameDirBase);
			if (len == 0 || gameDirBase[len-1] != '/')
				strcat(gameDirBase, "/");
			strcat(gameDirBase, ".pacman_sdl/");
		}
	}
	strcpy(filePath, gameDirBase);
	if (fileName)
		strcat(filePath, fileName);
}

void createGameDir() {
	char gameDir[256];
	getGameDirPath(gameDir, NULL);
#ifdef _WIN32
	_mkdir(gameDir);
#else
	mkdir(gameDir, 0770);  // rwxrwx---
#endif
}

bool fileExists(const char *filePath) {
#ifdef _WIN32
	return (0 == _access(filePath, 0));
#else
	return (0 == access(filePath, 0));
#endif
}

bool isDirectory(const char *path) {
	struct stat s;
	if (stat(path, &s) >= 0) {
		return (s.st_mode & S_IFDIR) != 0;
	} else if (errno == ENOENT) {
		// ENOENT = the path simply does not exist, so it cannot point to a directory.
		return false;
	} else {
		// another problem occured (access, memory, etc.)
		std::cerr << "isDirectory: stat failed (errno=" << errno << ")." << std::endl;
		return false;
	}
}
