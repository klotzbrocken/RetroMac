#include "pacman.h"
#include "config.h"

int main(int argc, char *argv[]) {
	srand((unsigned int) time(0));  // init randomize

	CommandLineOptions::set(argc, argv);
	if (CommandLineOptions::exists("h", "help")) {
		std::cout << "This game is a Pacman clone (version " << VERSION << ")."              << std::endl
		          << "Usage: pacman [options]"                                               << std::endl
		          << std::endl
		          << "Options:"                                                              << std::endl
		          << "  -h, --help         Display this help message and quit."              << std::endl
		          << "  -f, --fullscreen   Start the game in fullscreen mode."               << std::endl
		          << "  --noscaling        Do not try to scale the game in fullscreen mode." << std::endl
		          << "  --nocentering      Do not center the game in fullscreen mode."       << std::endl
		          << "  -s, --nosound      Start with sound switched off."                   << std::endl
		          << "  -m, --nomusic      Start with music switched off."                   << std::endl
		          << "  -v, --version      Print version number and quit."                   << std::endl
		          << "  --name=...         Provide the player's name."                       << std::endl
		          << "  --highscore=...    Define path to highscore file."                   << std::endl
		          << "  --hs-key=...       Highscore encryption key (hexadecimal)."          << std::endl
		          << std::endl;
		return EXIT_SUCCESS;
	}
	else if (CommandLineOptions::exists("v", "version")) {
		std::cout << "pacman version " << VERSION << std::endl;
		return EXIT_SUCCESS;
	}

	if(Screen::getInstance()->hasSDLInitErrorOccured())
		return EXIT_FAILURE;

	while(MenuMain::getInstance()->show()) {
		Game::getInstance()->start();
		if (Game::getInstance()->isGameOver()) {
			// do not load() here, this has been done at the time the game was over
			if (!HighscoreList::getInstance()->isReadonly()) {
				HighscoreList::getInstance()->show(true, true);  // player name alterable, last entry highlighted
				if (HighscoreList::getInstance()->getIdxLastInsertedEntry() >= 0) {
					HighscoreEntry *entry = HighscoreList::getInstance()->getEntry(HighscoreList::getInstance()->getIdxLastInsertedEntry());
					entry = new HighscoreEntry(std::string(entry->getPlayerName()), entry->getScore(), entry->getLevel());
					HighscoreList::getInstance()->load();
					HighscoreList::getInstance()->insertEntry(entry);
					HighscoreList::getInstance()->save();
				}
				HighscoreList::getInstance()->show(false, true);
			}
		}
	}

	Game::cleanUpInstance();
	MenuMain::cleanUpInstance();
	Labyrinth::cleanUpInstance();
	Pacman::cleanUpInstance();
	Ghost::cleanUpGhostArray();
	GameController::cleanUpInstance();
	Sounds::cleanUpInstance();
	Screen::cleanUpInstance();
	HighscoreList::cleanUpInstance();
	CommandLineOptions::cleanUp();

	return EXIT_SUCCESS;
}
