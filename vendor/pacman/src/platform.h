#ifndef PLATFORM_H
#define PLATFORM_H

#include <string.h>
#include <stdlib.h>
#include <errno.h>
#ifdef _WIN32
#include <direct.h>
#include <io.h>
#include <sys/stat.h>
#include <sys/types.h>
#else
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#endif
#include <iostream>

void getFilePath(char filePath[], const char file[]);

void getGameDirPath(char filePath[], const char fileName[]);

void createGameDir();

bool fileExists(const char *filePath);

bool isDirectory(const char *path);

#endif
