#ifndef SCREEN_H
#define SCREEN_H

#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <iostream>
#include "cmdline_options.h"
#include "constants.h"
#include "platform.h"

class Screen {
	public:
		static Screen *getInstance();
		static void cleanUpInstance();

	    // initialization
        // return whether an occured during the initialization of SDL
        bool hasSDLInitErrorOccured() {
            return sdlInitErrorOccured;
        }

        // methods for drawing
		// register graphic parts for updating
		void AddUpdateRects(int x, int y, int w, int h);  // should be renamed to addUpdateRect
		void addTotalUpdateRect();
		void addUpdateClipRect();
		// actually display the updated rectangles
		void Refresh();

		void draw_dynamic_content(SDL_Surface *surface, int x, int y);

		SDL_Window* getWindow() { return window; };

		// return the screen surface pointer
		SDL_Surface* getSurface() {
		    return screen_surface;
		}

		// return the screen texture
		SDL_Texture* getTexture() {
			return txScreenSurface;
		}
		// draw another graphic to the screen's surface
		void draw(SDL_Surface* graphic, int offset_x = 0, int offset_y = 0);

		// methods for fullscreen mode
		// return whether fullscreen mode is set
		bool isFullscreen() {
		    return fullscreen;
		}
		// switch to/from fullscreen
		void setFullscreen(bool fs);
		// toggle fullscreen mode
		void toggleFullscreen() {
		    setFullscreen(!fullscreen);
		}

		void clear();
		void clearOutsideClipRect();

		static SDL_Surface *loadImage(const char *filename, int transparentColor = -1);
		static TTF_Font *loadFont(const char *filename, int ptSize);
		static SDL_Surface *getTextSurface(TTF_Font *font, const char *text, SDL_Color color);
		//SDL_Renderer *getRenderer();

		// draw a filled rectangle
		void fillRect(SDL_Rect *rect, Uint8 r, Uint8 g, Uint8 b);

		static TTF_Font *getSmallFont();
		static TTF_Font *getFont();
		static TTF_Font *getLargeFont();
		static TTF_Font *getVeryLargeFont();
		static TTF_Font *getHugeFont();

		int getOffsetX() { return clipRect.x; }
		int getOffsetY() { return clipRect.y; }
		int getScalingFactor() { return scalingFactor; }

		// transforms x, y coordinates from screen (e.g. by mouse event) to game coordinates,
		// within the clipping rectangle, also considering its offset and scaling factor.
		static int xToClipRect(int x);
		static int yToClipRect(int y);

	private:
		static Screen *instance;
        // constructor and destructor
		Screen();
		~Screen();
		SDL_Window *window;
		SDL_Rect rects[Constants::MAX_UPDATE_RECTS], clipRect;
		int rect_num;
		SDL_Surface *screen_surface;
		SDL_Texture *txScreenSurface;
		bool sdlInitErrorOccured;
		bool fullscreen;
		bool beosFrame;     // draw BeOS window chrome (RETROMAC_THEME=beos)
		bool macos9Frame;   // draw Mac OS 9 Platinum chrome (RETROMAC_THEME=macos9)
		bool winxpFrame;    // draw Windows XP Luna chrome (RETROMAC_THEME=winxp)
		bool themedFrame;   // beosFrame || macos9Frame || winxpFrame
		int frameBorder;    // side/bottom frame width for the active theme
		int frameTitleH;    // top title strip height for the active theme
		static TTF_Font *smallFont, *font, *largeFont, *veryLargeFont, *hugeFont;
		void computeClipRect();
		void drawFrame();        // initial full paint (bg + chrome)
		void drawChrome();       // chrome around the game (every frame) — dispatches by theme
		void drawBeOSChrome();
		void drawMac9Chrome();
		void drawWinXPChrome();
		int scalingFactor;
};
#endif
