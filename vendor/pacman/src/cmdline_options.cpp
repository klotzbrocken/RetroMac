#include "cmdline_options.h"

int CommandLineOptions::num_args = 0;
std::string **CommandLineOptions::args = NULL;

void CommandLineOptions::set(int argc, char **argv) {
	cleanUp();
	num_args = argc;
	args = new std::string*[argc];
	for (int i = 0; i < argc; i++)
		args[i] = new std::string(argv[i]);
}

void CommandLineOptions::cleanUp() {
	for (int i = 0; i < num_args; i++)
		delete args[i];
	num_args = 0;
	if (args) {
		delete[] args;
		args = NULL;
	}
}

bool CommandLineOptions::exists(std::string unixStyle, std::string gnuStyle) {
	for (int i = 1; i < num_args; i++) {  // 0 is the program executable's path
		if (*args[i] == "--") {
			// end of options reached
			return false;
		} else if (args[i]->size() >= 2 && args[i]->substr(0,2) == "--") {
			// style: --option
			if (gnuStyle != "" && args[i]->substr(2) == gnuStyle)
				return true;
		} else if (args[i]->size() >= 1 && args[i]->substr(0,1) == "-") {
			// style: -o
			// or more than one option: -aVo
			if (unixStyle != "" && args[i]->find(unixStyle, 1) != std::string::npos) {
				return true;
			}
		}
	}
	return false;
}

std::string CommandLineOptions::getValue(std::string unixStyle, std::string gnuStyle) {
	for (int i = 1; i < num_args; i++) {  // 0 is the program executable's path
		if (*args[i] == "--") {
			// end of options reached
			return "";
		} else if (args[i]->size() >= 2 && args[i]->substr(0,2) == "--") {
			if (gnuStyle != "" && args[i]->substr(2, gnuStyle.size()) == gnuStyle) {
				if (args[i]->size() == gnuStyle.size()+2) {
					// style: --key value
					return ((i < num_args-1) ? *args[i+1] : "");
				} else if (args[i]->substr(gnuStyle.size()+2, 1) == "=") {
					// style: --key=value
					return args[i]->substr(gnuStyle.size()+3);
				}
			}
		} else if (args[i]->size() == 2 && *args[i] == std::string("-")+unixStyle) {
			// style: -k value
			return ((i < num_args-1) ? *args[i+1] : "");
		}
	}
	return "";
}
