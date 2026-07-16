#include "screen.h"
#include <cstdlib>
#include <cstring>
#include "stb_image.h"

// Load an image via stb_image (PNG/JPG/BMP/GIF, no external codec libs) into an RGBA SDL_Surface.
// Replaces SDL2_image's IMG_Load, which dragged in the whole libavif/jxl/aom/tiff/webp chain.
static SDL_Surface *stbLoadSurface(const char *path) {
	int w, h, comp;
	unsigned char *data = stbi_load(path, &w, &h, &comp, 4);   // force 4-channel RGBA
	if (!data) return NULL;
	SDL_Surface *surf = SDL_CreateRGBSurfaceWithFormat(0, w, h, 32, SDL_PIXELFORMAT_RGBA32);
	if (surf) {
		SDL_LockSurface(surf);
		for (int y = 0; y < h; y++)
			memcpy((unsigned char *)surf->pixels + y * surf->pitch, data + (size_t)y * w * 4, (size_t)w * 4);
		SDL_UnlockSurface(surf);
	}
	stbi_image_free(data);
	return surf;
}

// ---- BeOS window-chrome geometry (borderless theming) ----
static const int BEOS_BORDER  = 4;       // side/bottom frame
static const int BEOS_TITLE_H = 26;      // top title-tab strip
static const int BEOS_TAB_W   = 168;     // yellow Lasche width
static const SDL_Rect BEOS_CLOSE = { 8, 7, 14, 14 };   // close box (window coords)
// ---- Mac OS 9 (Platinum) window-chrome geometry ----
static const int MAC9_BORDER  = 2;       // thin side/bottom frame
static const int MAC9_TITLE_H = 22;      // full-width title bar
static const SDL_Rect MAC9_CLOSE = { 8, 5, 13, 13 };   // close box, left
// ---- Windows XP (Luna) window-chrome geometry ----
static const int WINXP_BORDER  = 4;      // blue sizing frame
static const int WINXP_TITLE_H = 30;     // full-width title bar

static const int MAC6_BORDER  = 2;       // thin black side/bottom frame (System 6)
static const int MAC6_TITLE_H = 22;      // full-width racing-stripe title bar
static const SDL_Rect MAC6_CLOSE = { 8, 5, 13, 13 };   // hollow close box, left

// Theme state shared with the static SDL callbacks (one theme per process).
static bool        g_controls = false;   // has minimise/maximise boxes (Mac OS 9 / XP)
static int         g_titleH   = BEOS_TITLE_H;
static SDL_Rect    g_close    = BEOS_CLOSE;
static SDL_Rect    g_collapse = {0, 0, 0, 0};   // Mac OS 9 WindowShade box
static SDL_Rect    g_zoom     = {0, 0, 0, 0};   // Mac OS 9 zoom box
static SDL_Window *g_win      = NULL;

static inline bool inRect(const SDL_Rect &r, int x, int y) {
	return r.w > 0 && x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h;
}
// Drag the borderless window by the title strip (but not the control boxes).
static SDL_HitTestResult themedHitTest(SDL_Window*, const SDL_Point *p, void*) {
	if (p->y < g_titleH && !inRect(g_close, p->x, p->y)
	    && !inRect(g_collapse, p->x, p->y) && !inRect(g_zoom, p->x, p->y))
		return SDL_HITTEST_DRAGGABLE;
	return SDL_HITTEST_NORMAL;
}
// Title-bar control boxes: close → quit; (Mac OS 9) collapse → minimise, zoom → fullscreen.
static int themedEventWatch(void*, SDL_Event *e) {
	if (e->type == SDL_MOUSEBUTTONDOWN && e->button.button == SDL_BUTTON_LEFT) {
		int x = e->button.x, y = e->button.y;
		if (inRect(g_close, x, y)) {
			SDL_Event q; q.type = SDL_QUIT; SDL_PushEvent(&q);
		} else if (g_controls && g_win && inRect(g_collapse, x, y)) {
			SDL_MinimizeWindow(g_win);
		} else if (g_controls && g_win && inRect(g_zoom, x, y)) {
			Uint32 fs = SDL_GetWindowFlags(g_win) & SDL_WINDOW_FULLSCREEN_DESKTOP;
			Screen::getInstance()->setFullscreen(fs == 0);
		}
	}
	return 1;
}

TTF_Font *Screen::smallFont     = NULL;
TTF_Font *Screen::font          = NULL;
TTF_Font *Screen::largeFont     = NULL;
TTF_Font *Screen::veryLargeFont = NULL;
TTF_Font *Screen::hugeFont      = NULL;

Screen *Screen::instance = NULL;

Screen *Screen::getInstance() {
	if (!instance) {
		instance = new Screen();
	}
	return instance;
}

void Screen::cleanUpInstance() {
	if (smallFont) {
		TTF_CloseFont(smallFont);
		smallFont = NULL;
	}
	if (font) {
		TTF_CloseFont(font);
		font = NULL;
	}
	if (largeFont) {
		TTF_CloseFont(largeFont);
		largeFont = NULL;
	}
	if (veryLargeFont) {
		TTF_CloseFont(veryLargeFont);
		veryLargeFont = NULL;
	}
	if (hugeFont) {
		TTF_CloseFont(hugeFont);
		hugeFont = NULL;
	}
	if (instance) {
		delete instance;
		instance = NULL;
	}
}

Screen::Screen():
	sdlInitErrorOccured(false),
	fullscreen(CommandLineOptions::exists("f","fullscreen")),
	rect_num(0),
	scalingFactor(1)
{
	// The host (RetroMac) passes its active theme; draw the BeOS Lasche only for BeOS.
	// Standalone (no env) defaults to the BeOS frame. Other themes → plain window.
	const char *th = getenv("RETROMAC_THEME");
	beosFrame   = (th == NULL) || (strcmp(th, "beos") == 0);
	macos9Frame = (th != NULL) && (strcmp(th, "macos9") == 0);
	winxpFrame  = (th != NULL) && (strcmp(th, "winxp")  == 0);
	macos6Frame = (th != NULL) && (strcmp(th, "macos6") == 0);
	themedFrame = beosFrame || macos9Frame || winxpFrame || macos6Frame;
	if (macos9Frame)      { frameBorder = MAC9_BORDER;  frameTitleH = MAC9_TITLE_H;  g_close = MAC9_CLOSE; }
	else if (macos6Frame) { frameBorder = MAC6_BORDER;  frameTitleH = MAC6_TITLE_H;  g_close = MAC6_CLOSE; }
	else if (winxpFrame)  { frameBorder = WINXP_BORDER; frameTitleH = WINXP_TITLE_H; }   // g_close set at draw time (right)
	else                  { frameBorder = BEOS_BORDER;  frameTitleH = BEOS_TITLE_H;  g_close = BEOS_CLOSE; }
	g_controls = macos9Frame || winxpFrame; g_titleH = frameTitleH;   // System 6 has only a close box
	// initialize SDL
	if(SDL_InitSubSystem(SDL_INIT_VIDEO) != 0) {
		std::cout << "SDL video initialization failed: " << SDL_GetError() << std::endl;
        sdlInitErrorOccured = true;
    }
	if(!sdlInitErrorOccured && TTF_Init() == -1) {
		std::cout << "TTF initialization failed: " << TTF_GetError() << std::endl;
        sdlInitErrorOccured = true;
	}
	if (!sdlInitErrorOccured) {
		bool chrome = themedFrame && !fullscreen;
		window = SDL_CreateWindow("Pacman",
								  SDL_WINDOWPOS_CENTERED,
                                  SDL_WINDOWPOS_CENTERED,
                           		  chrome ? Constants::WINDOW_WIDTH  + 2 * frameBorder            : Constants::WINDOW_WIDTH,
                           		  chrome ? Constants::WINDOW_HEIGHT + frameTitleH + frameBorder  : Constants::WINDOW_HEIGHT,
                           		  fullscreen ? SDL_WINDOW_FULLSCREEN_DESKTOP : (chrome ? SDL_WINDOW_BORDERLESS : 0));
		g_win = window;
		screen_surface = SDL_GetWindowSurface(window);
		computeClipRect();
		if(screen_surface == 0) {
			std::cout << "Setting video mode failed: " << SDL_GetError() << std::endl;
			sdlInitErrorOccured = true;
		} else if (chrome) {
			// Themed chrome: native drag by the title strip, click-to-close, painted frame.
			SDL_SetWindowHitTest(window, themedHitTest, NULL);
			SDL_AddEventWatch(themedEventWatch, NULL);
			drawFrame();
			SDL_UpdateWindowSurface(window);
		}
	}
	atexit(Screen::cleanUpInstance);
}

Screen::~Screen() {
	TTF_Quit();
	SDL_QuitSubSystem(SDL_INIT_VIDEO | SDL_INIT_GAMECONTROLLER);
}

void Screen::AddUpdateRects(int x, int y, int w, int h) {
	if (rect_num >= Constants::MAX_UPDATE_RECTS)
		return;  // prevent index out of bounds problems
	if (x < 0) {
		w += x;
		x = 0;
	}
	if (y < 0) {
		h += y;
		y = 0;
	}
	if (x + w > clipRect.w)
		w = clipRect.w - x;
	if (y + h > clipRect.h)
		h = clipRect.h - y;
	if (w <= 0 || h <= 0)
		return;
	rects[rect_num].x = (short int) x*scalingFactor + clipRect.x;
	rects[rect_num].y = (short int) y*scalingFactor + clipRect.y;
	rects[rect_num].w = (short int) w * scalingFactor;
	rects[rect_num].h = (short int) h * scalingFactor;
	rect_num++;
}

void Screen::addTotalUpdateRect() {
	rects[0].x = 0;
	rects[0].y = 0;
	rects[0].w = screen_surface->w;  // no scalingFactor as screen_surface already is the total screen surface
	rects[0].h = screen_surface->h;
	rect_num = 1;  // all other update rects will be included in this one
}

void Screen::addUpdateClipRect() {
	AddUpdateRects(0, 0, Constants::WINDOW_WIDTH, Constants::WINDOW_HEIGHT);
}

void Screen::Refresh() {
	if (macos6Frame) monochromeGameArea();   // desaturate the just-drawn game to 1-bit-ish B/W
	if (themedFrame && !fullscreen) {
		// Repaint the chrome and update the whole window — SDL's window surface
		// doesn't reliably keep un-updated regions on macOS, so a once-drawn frame vanishes.
		drawChrome();
		SDL_UpdateWindowSurface(window);
	} else {
		SDL_UpdateWindowSurfaceRects(window, rects, rect_num);
	}
	rect_num = 0;
}

void Screen::draw_dynamic_content(SDL_Surface *surface, int x, int y) {
	SDL_Rect dest;
	dest.x = (short int) x*scalingFactor + clipRect.x;
	dest.y = (short int) y*scalingFactor + clipRect.y;
	dest.w = (short int) surface->w * scalingFactor;
	dest.h = (short int) surface->h * scalingFactor;
	if (scalingFactor > 1) {
		SDL_BlitScaled(surface, NULL, screen_surface, &dest);
	} else {
		SDL_BlitSurface(surface, NULL, screen_surface, &dest);
	}
	AddUpdateRects(x, y, surface->w + 10, surface->h);
}

void Screen::draw(SDL_Surface* graphic, int offset_x, int offset_y) {
    if (0 == offset_x && 0 == offset_y && 0 == clipRect.x && 0 == clipRect.y && scalingFactor == 1) {
        SDL_BlitSurface(graphic, NULL, screen_surface, NULL);
    } else {
        SDL_Rect position;
        position.x = (short int) offset_x*scalingFactor + clipRect.x;
        position.y = (short int) offset_y*scalingFactor + clipRect.y;
		position.w = (short int) graphic->w * scalingFactor;
		position.h = (short int) graphic->h * scalingFactor;
		if (scalingFactor > 1) {
			SDL_BlitScaled(graphic, NULL, screen_surface, &position);
		} else {
			SDL_BlitSurface(graphic, NULL, screen_surface, &position);
		}
    }
}

void Screen::setFullscreen(bool fs) {
	if (fs == fullscreen) {
		return;  // the desired mode already has been activated, so do nothing
	}
	if (fs) {
		SDL_SetWindowFullscreen(window, SDL_WINDOW_FULLSCREEN_DESKTOP);
	} else {
		SDL_SetWindowFullscreen(window, 0);
		SDL_SetWindowSize(window,
		    themedFrame ? Constants::WINDOW_WIDTH  + 2 * frameBorder           : Constants::WINDOW_WIDTH,
		    themedFrame ? Constants::WINDOW_HEIGHT + frameTitleH + frameBorder : Constants::WINDOW_HEIGHT);
		SDL_SetWindowPosition(window, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED);
	}
	SDL_Surface* newScreen = SDL_GetWindowSurface(window);
	if(newScreen) {
		screen_surface = newScreen;
		fullscreen = fs;          // computeClipRect() branches on this
		computeClipRect();
		if (fs) { clearOutsideClipRect(); } else if (themedFrame) { drawFrame(); }
		addTotalUpdateRect();
	} else {
		if (fs) {
			std::cout << "Switching to fullscreen mode failed: " << SDL_GetError() << std::endl;
		} else {
			std::cout << "Switching from fullscreen mode failed: " << SDL_GetError() << std::endl;
		}
	}
}

SDL_Surface *Screen::loadImage(const char *filename, int transparentColor) {
	char filePath[256];
	getFilePath(filePath, filename);
	SDL_Surface *surface, *temp;
	temp = stbLoadSurface(filePath);
	if (!temp) {
		std::cout << "Unable to load image: " << (stbi_failure_reason() ? stbi_failure_reason() : "unknown") << std::endl;
		exit(EXIT_FAILURE);
	}
	surface = SDL_ConvertSurface(temp,  Screen::getInstance()->getSurface()->format, 0);
	if (surface == NULL) {
		std::cout << "Unable to convert image to display format: " << SDL_GetError() << std::endl;
		exit(EXIT_FAILURE);
	}
	// stb_image gives every surface an alpha channel (→ SDL_BLENDMODE_BLEND), which makes the
	// colour-key blit ignore the key and draw an opaque box. Force NONE so keying works exactly
	// like the old SDL_image (RGB) path.
	SDL_SetSurfaceBlendMode(surface, SDL_BLENDMODE_NONE);
	if (transparentColor != -1) {
		if (SDL_SetColorKey(surface, SDL_TRUE, (Uint32)SDL_MapRGB(surface->format, (uint8_t)transparentColor, (uint8_t)transparentColor, (uint8_t)transparentColor))) {
			std::cout << "Unable to set transparent color: " << SDL_GetError() << std::endl;
		}
	}
	if (SDL_SetSurfaceRLE(surface, SDL_TRUE) < 0) {
		std::cout << "Unable to enable RLE: " << SDL_GetError() << std::endl;
	}
	SDL_FreeSurface(temp);
	return surface;
}

TTF_Font *Screen::loadFont(const char *filename, int ptSize) {
	char filePath[256];
	getFilePath(filePath, filename);
	TTF_Font *font = TTF_OpenFont(filePath, ptSize);
	if (!font) {
		std::cout << "Unable to open TTF font: " << TTF_GetError() << std::endl;
		exit(EXIT_FAILURE);
	}
	return font;
}

SDL_Surface *Screen::getTextSurface(TTF_Font *font, const char *text, SDL_Color color) {
	SDL_Surface *temp = TTF_RenderText_Solid(font, text, color);
	if (!temp) {
		std::cout << "Unable to render text \"" << text << "\": " << TTF_GetError() << std::endl;
		exit(EXIT_FAILURE);
	}
	SDL_Surface *surface = SDL_ConvertSurface(temp,  Screen::getInstance()->getSurface()->format, 0);
	if (surface == NULL) {
		std::cout << "Unable to convert text surface to display format: " << SDL_GetError() << std::endl;
		exit(EXIT_FAILURE);
	}
	SDL_FreeSurface(temp);
	return surface;
}

void Screen::clear() {
	// Clear only the game area so the painted BeOS frame around it persists.
	SDL_Rect rect = { clipRect.x, clipRect.y, clipRect.w * scalingFactor, clipRect.h * scalingFactor };
	SDL_FillRect(screen_surface, &rect, SDL_MapRGB(screen_surface->format, 0, 0, 0));
}

void Screen::clearOutsideClipRect() {
	SDL_Rect rect;
	if (clipRect.x > 0) {
		rect.x = 0;
		rect.y = 0;
		rect.w = clipRect.x;
		rect.h = screen_surface->h;
		SDL_FillRect(screen_surface, &rect, SDL_MapRGB(screen_surface->format, 0, 0, 0));
	}
	if (clipRect.x + clipRect.w*scalingFactor < screen_surface->w) {
		rect.x = clipRect.x + clipRect.w*scalingFactor;
		rect.y = 0;
		rect.w = screen_surface->w - rect.x;
		rect.h = screen_surface->h;
		SDL_FillRect(screen_surface, &rect, SDL_MapRGB(screen_surface->format, 0, 0, 0));
	}
	if (clipRect.y > 0) {
		rect.x = clipRect.x;
		rect.y = 0;
		rect.w = clipRect.w*scalingFactor;
		rect.h = clipRect.y;
		SDL_FillRect(screen_surface, &rect, SDL_MapRGB(screen_surface->format, 0, 0, 0));
	}
	if (clipRect.y + clipRect.h*scalingFactor < screen_surface->h) {
		rect.x = clipRect.x;
		rect.y = clipRect.y + clipRect.h*scalingFactor;
		rect.w = clipRect.w*scalingFactor;
		rect.h = screen_surface->h - rect.y;
		SDL_FillRect(screen_surface, &rect, SDL_MapRGB(screen_surface->format, 0, 0, 0));
	}
}

static SDL_Surface *beosTitleSurf = NULL;   // cached "Pacman" title text

// Initial full paint: window bg + black game area + chrome.
void Screen::drawFrame() {
	Uint32 bg;
	if (winxpFrame)       bg = SDL_MapRGB(screen_surface->format, 0x08, 0x31, 0xD9);   // Luna blue frame
	else if (macos9Frame) bg = SDL_MapRGB(screen_surface->format, 0xD8, 0xD8, 0xD8);
	else if (macos6Frame) bg = SDL_MapRGB(screen_surface->format, 0xFF, 0xFF, 0xFF);   // System 6 white
	else                  bg = SDL_MapRGB(screen_surface->format, 0xD6, 0xD6, 0xD6);
	SDL_FillRect(screen_surface, NULL, bg);
	SDL_FillRect(screen_surface, &clipRect, SDL_MapRGB(screen_surface->format, 0, 0, 0));
	drawChrome();
}

// Paints ONLY the chrome around the game area (called every frame, since SDL's window
// surface doesn't reliably persist un-updated regions on macOS). Never touches the game area.
void Screen::drawChrome() {
	if (winxpFrame)       drawWinXPChrome();
	else if (macos9Frame) drawMac9Chrome();
	else if (macos6Frame) drawMac6Chrome();
	else                  drawBeOSChrome();
}

// Windows XP (Luna Blue) window: gradient title bar, system icon left, min/max/close right.
void Screen::drawWinXPChrome() {
	SDL_PixelFormat *f = screen_surface->format;
	Uint32 white = SDL_MapRGB(f, 0xFF, 0xFF, 0xFF);
	Uint32 face  = SDL_MapRGB(f, 0xEC, 0xE9, 0xD8);
	auto line = [&](int x, int y, int w, int h, Uint32 c){ SDL_Rect r = {x,y,w,h}; SDL_FillRect(screen_surface, &r, c); };

	int W = screen_surface->w, H = screen_surface->h;
	int gx = clipRect.x, gy = clipRect.y, gw = clipRect.w, gh = clipRect.h;
	int T = WINXP_TITLE_H;

	// blue frame bands around the game area (left/right/bottom 4px; title strip on top)
	{ SDL_Rect r; Uint32 blue = SDL_MapRGB(f, 0x08, 0x31, 0xD9);
	  r = {0,gy,gx,gh}; SDL_FillRect(screen_surface,&r,blue);
	  r = {gx+gw,gy,W-(gx+gw),gh}; SDL_FillRect(screen_surface,&r,blue);
	  r = {0,gy+gh,W,H-(gy+gh)}; SDL_FillRect(screen_surface,&r,blue); }
	// outer darker edge
	{ Uint32 edge = SDL_MapRGB(f, 0x00, 0x26, 0xA3);
	  line(0,0,W,1,edge); line(0,0,1,H,edge); line(W-1,0,1,H,edge); line(0,H-1,W,1,edge); }

	// title-bar vertical gradient (full width)
	auto lerp = [](int a, int b, double u) -> Uint8 { return (Uint8)(a + u * (b - a)); };
	for (int y = 0; y < T; y++) {
		double t = (double)y / (T - 1);
		Uint8 r, g, b;
		if (t < 0.5) { double u = t / 0.5;       r = lerp(0x09, 0x00, u); g = lerp(0x97, 0x53, u); b = lerp(0xFF, 0xEE, u); }
		else         { double u = (t - 0.5)/0.5; r = lerp(0x00, 0x00, u); g = lerp(0x66, 0x3D, u); b = lerp(0xFF, 0xD2, u); }
		line(0, y, W, 1, SDL_MapRGB(f, r, g, b));
	}

	Uint32 glint  = SDL_MapRGB(f, 0xFF, 0xFF, 0xFF);
	Uint32 edge   = SDL_MapRGB(f, 0x00, 0x1A, 0x6E);   // dark blue button outline

	// system icon (left): a small framed tile so it's clearly visible on the blue bar
	SDL_Rect sysi = { 6, (T - 16)/2, 16, 16 };
	SDL_FillRect(screen_surface, &sysi, SDL_MapRGB(f, 0xCF, 0xE0, 0xFF));
	{ SDL_Rect c = {7,(T-16)/2+1,14,14}; SDL_FillRect(screen_surface,&c,SDL_MapRGB(f,0x3B,0x6E,0xD8)); }
	line(sysi.x, sysi.y, sysi.w, 1, white); line(sysi.x, sysi.y, 1, sysi.h, white);
	line(sysi.x, sysi.y+sysi.h-1, sysi.w, 1, edge); line(sysi.x+sysi.w-1, sysi.y, 1, sysi.h, edge);

	// caption buttons (right): minimise, maximise, close — solid + bordered for guaranteed contrast
	int bs = 21, by = (T - bs)/2, gap = 2, cw = 23;
	SDL_Rect close = { W - 4 - cw, by, cw, bs };
	SDL_Rect maxb  = { close.x - gap - bs, by, bs, bs };
	SDL_Rect minb  = { maxb.x  - gap - bs, by, bs, bs };
	g_close = close; g_collapse = minb; g_zoom = maxb;   // close right; min/max to its left
	auto capBtn = [&](SDL_Rect b, Uint32 fillc){
		SDL_FillRect(screen_surface, &b, fillc);
		line(b.x, b.y, b.w, 1, glint);  line(b.x, b.y, 1, b.h, glint);            // top/left highlight
		line(b.x, b.y+b.h-1, b.w, 1, edge);  line(b.x+b.w-1, b.y, 1, b.h, edge);  // bottom/right edge
	};
	Uint32 blueBtn = SDL_MapRGB(f, 0x1D, 0x63, 0xF0);
	Uint32 redBtn  = SDL_MapRGB(f, 0xD0, 0x3A, 0x29);
	capBtn(minb, blueBtn); capBtn(maxb, blueBtn); capBtn(close, redBtn);
	// glyphs (white)
	line(minb.x+5, minb.y+bs-7, bs-10, 2, white);                                  // minimise underscore
	{ SDL_Rect mr = { maxb.x+5, maxb.y+5, bs-10, bs-10 }; line(mr.x,mr.y,mr.w,3,white);
	  line(mr.x,mr.y,1,mr.h,white); line(mr.x+mr.w-1,mr.y,1,mr.h,white); line(mr.x,mr.y+mr.h-1,mr.w,1,white); }
	for (int i = 0; i < 9; i++) {                                                   // close X
		line(close.x + 7 + i, close.y + 6 + i, 2, 1, white);
		line(close.x + 7 + i, close.y + bs - 7 - i, 2, 1, white);
	}

	// title text (cached) just right of the system icon
	if (!beosTitleSurf) {
		SDL_Color tc = {0xFF, 0xFF, 0xFF, 255};
		beosTitleSurf = TTF_RenderText_Solid(getSmallFont(), "Pacman", tc);
	}
	if (beosTitleSurf) {
		SDL_Rect d = { sysi.x + sysi.w + 6, (T - beosTitleSurf->h)/2, beosTitleSurf->w, beosTitleSurf->h };
		SDL_BlitSurface(beosTitleSurf, NULL, screen_surface, &d);
	}
	(void)face;
}

// Mac OS 9 Platinum window: pinstripe title bar, close box left, collapse+zoom right.
void Screen::drawMac9Chrome() {
	SDL_PixelFormat *f = screen_surface->format;
	Uint32 face   = SDL_MapRGB(f, 0xD8, 0xD8, 0xD8);
	Uint32 black  = SDL_MapRGB(f, 0, 0, 0);
	Uint32 light  = SDL_MapRGB(f, 0xFF, 0xFF, 0xFF);
	Uint32 dark   = SDL_MapRGB(f, 0x80, 0x80, 0x80);
	Uint32 darker = SDL_MapRGB(f, 0x55, 0x55, 0x55);
	Uint32 strLt  = SDL_MapRGB(f, 0xED, 0xED, 0xED);
	Uint32 strDk  = SDL_MapRGB(f, 0xBD, 0xBD, 0xBD);
	auto line = [&](int x, int y, int w, int h, Uint32 c){ SDL_Rect r = {x,y,w,h}; SDL_FillRect(screen_surface, &r, c); };
	auto box = [&](SDL_Rect b){ SDL_FillRect(screen_surface, &b, face);
		line(b.x, b.y, b.w, 1, light); line(b.x, b.y, 1, b.h, light);
		line(b.x, b.y + b.h - 1, b.w, 1, dark); line(b.x + b.w - 1, b.y, 1, b.h, dark); };

	int W = screen_surface->w, H = screen_surface->h;
	int gx = clipRect.x, gy = clipRect.y, gw = clipRect.w, gh = clipRect.h;

	// grey bands around the game area
	{ SDL_Rect r; r = {0,0,W,gy}; SDL_FillRect(screen_surface,&r,face);
	  r = {0,gy+gh,W,H-(gy+gh)}; SDL_FillRect(screen_surface,&r,face);
	  r = {0,gy,gx,gh}; SDL_FillRect(screen_surface,&r,face);
	  r = {gx+gw,gy,W-(gx+gw),gh}; SDL_FillRect(screen_surface,&r,face); }

	// outer black window frame
	line(0,0,W,1,black); line(0,0,1,H,black); line(0,H-1,W,1,black); line(W-1,0,1,H,black);
	// title-bar pinstripes
	for (int y = 1; y < MAC9_TITLE_H - 1; y += 2) { line(1,y,W-2,1,strLt); line(1,y+1,W-2,1,strDk); }
	line(0, MAC9_TITLE_H - 1, W, 1, dark);   // separator under the title bar
	// sunken frame around the game area
	line(gx-1, gy-1, gw+2, 1, dark); line(gx-1, gy-1, 1, gh+2, dark);

	// close box (left)
	box(g_close);
	// right-side control boxes: collapse + zoom
	int bs = g_close.h, by = g_close.y;
	SDL_Rect zoomR = { W - 2 - 7 - bs, by, bs, bs }; g_zoom = zoomR;
	SDL_Rect collR = { zoomR.x - 5 - bs, by, bs, bs }; g_collapse = collR;
	box(g_collapse); box(g_zoom);
	// zoom inner square
	line(g_zoom.x+2, g_zoom.y+2, bs-4, 1, darker); line(g_zoom.x+2, g_zoom.y+2, 1, bs-4, darker);
	line(g_zoom.x+2, g_zoom.y+bs-3, bs-4, 1, darker); line(g_zoom.x+bs-3, g_zoom.y+2, 1, bs-4, darker);
	// collapse inner line (WindowShade)
	line(g_collapse.x+3, g_collapse.y+3, bs-6, 1, darker);

	// title plaque (centered)
	if (!beosTitleSurf) {
		SDL_Color tc = {0, 0, 0, 255};
		beosTitleSurf = TTF_RenderText_Solid(getSmallFont(), "Pacman", tc);
	}
	if (beosTitleSurf) {
		int tw = beosTitleSurf->w, ty = (MAC9_TITLE_H - beosTitleSurf->h) / 2;
		SDL_Rect plaque = { (W - tw)/2 - 8, ty - 1, tw + 16, beosTitleSurf->h + 2 };
		SDL_FillRect(screen_surface, &plaque, face);
		SDL_Rect d = { (W - tw)/2, ty, tw, beosTitleSurf->h };
		SDL_BlitSurface(beosTitleSurf, NULL, screen_surface, &d);
	}
}

// Mac System 6 window: 1-bit racing-stripe title bar, hollow close box left, no zoom/collapse.
void Screen::drawMac6Chrome() {
	SDL_PixelFormat *f = screen_surface->format;
	Uint32 black = SDL_MapRGB(f, 0, 0, 0);
	Uint32 white = SDL_MapRGB(f, 0xFF, 0xFF, 0xFF);
	auto line = [&](int x, int y, int w, int h, Uint32 c){ SDL_Rect r = {x,y,w,h}; SDL_FillRect(screen_surface, &r, c); };

	int W = screen_surface->w, H = screen_surface->h;
	int gx = clipRect.x, gy = clipRect.y, gw = clipRect.w, gh = clipRect.h;
	int T = MAC6_TITLE_H;

	// white bands around the game area
	{ SDL_Rect r; r = {0,0,W,gy}; SDL_FillRect(screen_surface,&r,white);
	  r = {0,gy+gh,W,H-(gy+gh)}; SDL_FillRect(screen_surface,&r,white);
	  r = {0,gy,gx,gh}; SDL_FillRect(screen_surface,&r,white);
	  r = {gx+gw,gy,W-(gx+gw),gh}; SDL_FillRect(screen_surface,&r,white); }

	// racing-stripe title bar: fine full-width black lines every other row
	for (int y = 3; y <= T - 5; y += 2) line(6, y, W - 12, 1, black);
	// outer black window frame + separator under the title bar
	line(0,0,W,1,black); line(0,0,1,H,black); line(0,H-1,W,1,black); line(W-1,0,1,H,black);
	line(0, T - 1, W, 1, black);
	// 1px black outline around the game area (sunken look, System 6 style)
	line(gx-1, gy-1, gw+2, 1, black); line(gx-1, gy-1, 1, gh+2, black);
	line(gx-1, gy+gh, gw+2, 1, black); line(gx+gw, gy-1, 1, gh+2, black);

	// hollow close box (left): white fill + black outline
	SDL_Rect cb = g_close;
	SDL_FillRect(screen_surface, &cb, white);
	line(cb.x, cb.y, cb.w, 1, black); line(cb.x, cb.y+cb.h-1, cb.w, 1, black);
	line(cb.x, cb.y, 1, cb.h, black); line(cb.x+cb.w-1, cb.y, 1, cb.h, black);

	// title plaque (centered) — white block interrupting the stripes, black Chicago-ish text
	if (!beosTitleSurf) {
		SDL_Color tc = {0, 0, 0, 255};
		beosTitleSurf = TTF_RenderText_Solid(getSmallFont(), "Pacman", tc);
	}
	if (beosTitleSurf) {
		int tw = beosTitleSurf->w, ty = (T - beosTitleSurf->h) / 2;
		SDL_Rect plaque = { (W - tw)/2 - 10, 1, tw + 20, T - 2 };
		SDL_FillRect(screen_surface, &plaque, white);
		SDL_Rect d = { (W - tw)/2, ty, tw, beosTitleSurf->h };
		SDL_BlitSurface(beosTitleSurf, NULL, screen_surface, &d);
	}
}

// Desaturate the game area in place so Pac-Man matches System 6's monochrome (grayscale)
// look. Software surface → iterate clipRect pixels (luma), readable but colourless.
void Screen::monochromeGameArea() {
	if (SDL_MUSTLOCK(screen_surface) && SDL_LockSurface(screen_surface) != 0) return;
	SDL_PixelFormat *f = screen_surface->format;
	int bpp = f->BytesPerPixel;
	if (bpp != 4) { if (SDL_MUSTLOCK(screen_surface)) SDL_UnlockSurface(screen_surface); return; }
	int x0 = clipRect.x, y0 = clipRect.y, x1 = clipRect.x + clipRect.w, y1 = clipRect.y + clipRect.h;
	if (x0 < 0) x0 = 0; if (y0 < 0) y0 = 0;
	if (x1 > screen_surface->w) x1 = screen_surface->w;
	if (y1 > screen_surface->h) y1 = screen_surface->h;
	for (int y = y0; y < y1; y++) {
		Uint8 *row = (Uint8*)screen_surface->pixels + y * screen_surface->pitch;
		for (int x = x0; x < x1; x++) {
			Uint32 *p = (Uint32*)(row + x * bpp);
			Uint8 r, g, b; SDL_GetRGB(*p, f, &r, &g, &b);
			Uint8 lum = (Uint8)((r * 77 + g * 151 + b * 28) >> 8);   // Rec.601 luma
			*p = SDL_MapRGB(f, lum, lum, lum);
		}
	}
	if (SDL_MUSTLOCK(screen_surface)) SDL_UnlockSurface(screen_surface);
}

// BeOS window: yellow Lasche (flush-left) + close box.
void Screen::drawBeOSChrome() {
	SDL_PixelFormat *f = screen_surface->format;
	Uint32 grey    = SDL_MapRGB(f, 0xD6, 0xD6, 0xD6);
	Uint32 dark    = SDL_MapRGB(f, 0x2A, 0x2A, 0x2A);
	Uint32 light   = SDL_MapRGB(f, 0xFF, 0xFF, 0xFF);
	Uint32 shadow  = SDL_MapRGB(f, 0x8A, 0x8A, 0x8A);
	Uint32 yellow1 = SDL_MapRGB(f, 0xFB, 0xD8, 0x5C);
	Uint32 yellow2 = SDL_MapRGB(f, 0xF2, 0xBD, 0x23);
	Uint32 closeY  = SDL_MapRGB(f, 0xEA, 0xB9, 0x2A);
	auto line = [&](int x, int y, int w, int h, Uint32 c){ SDL_Rect r = {x,y,w,h}; SDL_FillRect(screen_surface, &r, c); };

	int W = screen_surface->w, H = screen_surface->h;
	int gx = clipRect.x, gy = clipRect.y, gw = clipRect.w, gh = clipRect.h;

	// grey bands around the game area (top / bottom / left / right) — leaves game untouched
	{ SDL_Rect r; r = {0,0,W,gy}; SDL_FillRect(screen_surface,&r,grey);
	  r = {0,gy+gh,W,H-(gy+gh)}; SDL_FillRect(screen_surface,&r,grey);
	  r = {0,gy,gx,gh}; SDL_FillRect(screen_surface,&r,grey);
	  r = {gx+gw,gy,W-(gx+gw),gh}; SDL_FillRect(screen_surface,&r,grey); }

	// raised outer bevel
	line(0, 0, W, 1, light);  line(0, 0, 1, H, light);
	line(0, H - 1, W, 1, shadow);  line(W - 1, 0, 1, H, shadow);

	// sunken frame around the game area
	line(gx - 2, gy - 2, gw + 4, 2, shadow);  line(gx - 2, gy - 2, 2, gh + 4, shadow);
	line(gx - 2, gy + gh, gw + 4, 2, light);  line(gx + gw, gy - 2, 2, gh + 4, light);
	line(gx - 1, gy - 1, gw + 2, 1, dark);    line(gx - 1, gy - 1, 1, gh + 2, dark);

	// yellow title tab (flush-left)
	SDL_Rect tab = {0, 0, BEOS_TAB_W, BEOS_TITLE_H};
	SDL_FillRect(screen_surface, &tab, yellow1);
	line(0, BEOS_TITLE_H / 2, BEOS_TAB_W, BEOS_TITLE_H / 2, yellow2);
	line(0, 0, BEOS_TAB_W, 1, dark);  line(0, 0, 1, BEOS_TITLE_H, dark);
	line(BEOS_TAB_W - 1, 0, 1, BEOS_TITLE_H, dark);  line(0, BEOS_TITLE_H - 1, BEOS_TAB_W, 1, dark);

	// close box
	SDL_Rect cb = BEOS_CLOSE;
	SDL_FillRect(screen_surface, &cb, closeY);
	line(cb.x, cb.y, cb.w, 1, dark);  line(cb.x, cb.y, 1, cb.h, dark);
	line(cb.x + cb.w - 1, cb.y, 1, cb.h, dark);  line(cb.x, cb.y + cb.h - 1, cb.w, 1, dark);

	// title text (cached)
	if (!beosTitleSurf) {
		SDL_Color tc = {0x2A, 0x23, 0x06, 255};
		beosTitleSurf = TTF_RenderText_Solid(getSmallFont(), "Pacman", tc);
	}
	if (beosTitleSurf) {
		SDL_Rect d = { cb.x + cb.w + 8, (BEOS_TITLE_H - beosTitleSurf->h) / 2, beosTitleSurf->w, beosTitleSurf->h };
		SDL_BlitSurface(beosTitleSurf, NULL, screen_surface, &d);
	}
}

void Screen::fillRect(SDL_Rect *rect, Uint8 r, Uint8 g, Uint8 b) {
	if (0 == clipRect.x && 0 == clipRect.y && scalingFactor == 1) {
		SDL_FillRect(screen_surface, rect, SDL_MapRGB(screen_surface->format, r, g, b));
	} else {
		SDL_Rect rect_moved;
		rect_moved.x = rect->x * scalingFactor + clipRect.x;
		rect_moved.y = rect->y * scalingFactor + clipRect.y;
		rect_moved.w = rect->w * scalingFactor;
		rect_moved.h = rect->h * scalingFactor;
		SDL_FillRect(screen_surface, &rect_moved, SDL_MapRGB(screen_surface->format, r, g, b));
	}
}

TTF_Font *Screen::getSmallFont() {
	if (!smallFont)
		smallFont = loadFont("fonts/Cheapmot.TTF", 12);
	return smallFont;
}
TTF_Font *Screen::getFont() {
	if (!font)
		font = loadFont("fonts/Cheapmot.TTF", 20);
	return font;
}
TTF_Font *Screen::getLargeFont() {
	if (!largeFont)
		largeFont = loadFont("fonts/Cheapmot.TTF", 24);
	return largeFont;
}
TTF_Font *Screen::getVeryLargeFont() {
	if (!veryLargeFont)
		veryLargeFont = loadFont("fonts/Cheapmot.TTF", 48);
	return veryLargeFont;
}
TTF_Font *Screen::getHugeFont() {
	if (!hugeFont)
		hugeFont = loadFont("fonts/Cheapmot.TTF", 96);
	return hugeFont;
}

void Screen::computeClipRect() {
	// BeOS windowed mode reserves a fixed frame (top tab + borders); the game renders
	// into the inset rect (all draws already add clipRect.x/y as an offset).
	if (!fullscreen && themedFrame) {
		clipRect.x = frameBorder;
		clipRect.y = frameTitleH;
		clipRect.w = Constants::WINDOW_WIDTH;
		clipRect.h = Constants::WINDOW_HEIGHT;
		scalingFactor = 1;
		return;
	}
	bool scaling_allowed = !CommandLineOptions::exists("","noscaling");
	bool centering_allowed = !CommandLineOptions::exists("","nocentering");
	if (screen_surface->w == Constants::WINDOW_WIDTH || !centering_allowed) {
		clipRect.x = 0;
	} else {
		clipRect.x = (screen_surface->w - Constants::WINDOW_WIDTH) >> 1;
		if (clipRect.x < 0)
			clipRect.x = 0;
	}
	clipRect.w = Constants::WINDOW_WIDTH;
	if (screen_surface->h == Constants::WINDOW_HEIGHT || !centering_allowed) {
		clipRect.y = 0;
	} else {
		clipRect.y = (screen_surface->h - Constants::WINDOW_HEIGHT) >> 1;
		if (clipRect.y < 0)
			clipRect.y = 0;
	}
	clipRect.h = Constants::WINDOW_HEIGHT;
	if (scaling_allowed) {
		int scalingX = screen_surface->w / clipRect.w;
		int scalingY = screen_surface->h / clipRect.h;
		scalingFactor = scalingX < scalingY ? scalingX : scalingY;
		if (scalingFactor < 1) {
			scalingFactor = 1;
		}
		if (scalingFactor >= 2 && centering_allowed) {
			clipRect.x = (screen_surface->w - clipRect.w * scalingFactor) >> 1;
			clipRect.y = (screen_surface->h - clipRect.h * scalingFactor) >> 1;
		}
	}
}

int Screen::xToClipRect(int x) {
	return (x - Screen::getInstance()->getOffsetX()) / Screen::getInstance()->getScalingFactor();
}

int Screen::yToClipRect(int y) {
	return (y - Screen::getInstance()->getOffsetY()) / Screen::getInstance()->getScalingFactor();
}
