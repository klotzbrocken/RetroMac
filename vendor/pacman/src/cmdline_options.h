#ifndef CMDLINE_OPTIONS_H
#define CMDLINE_OPTIONS_H

#include <string>

class CommandLineOptions {
	public:
		static void set(int argc, char **argv);
		static void cleanUp();
		static bool exists(std::string unixStyle, std::string gnuStyle = "");
		static std::string getValue(std::string unixStyle, std::string gnuStyle = "");
	private:
		static int num_args;
		static std::string **args;
};

#endif
