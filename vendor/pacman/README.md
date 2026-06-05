Pacman
======

![in-game screenshot](https://libregamewiki.org/images/1/18/Pacman.png "in-game screenshot")

This is a clone of the original pacman by Namco, as I remember, that I played for the first time on an Atari 130 XL in the early 90s.

Also, Paul Neave's pacman clone has inspired me greatly.

One of the main goals of this implementation is an SDL application with a very low CPU usage.


## Install hint ##

You have to compile the Linux version on your own. For this, you'll need
* libsdl2
* sdl2-image
* sdl2-ttf
* and sdl2-mixer.

(make sure to take the devel packages) 
Then, download and extract the zip file or clone the pacman repository.
Inside the pacman directory, run
```
./configure
make
make install
```
For more detailed instructions, you may also have a look at the [INSTALL](https://github.com/ebuc99/pacman/blob/master/INSTALL) file.

After a successful installation, you should be able to start the game via command line: `pacman`

## Install Fedora ##

```
sudo dnf install make gcc-c++ SDL2 SDL2-devel SDL2_image SDL2_image-devel SDL2_mixer SDL2_mixer-devel SDL2_ttf SDL2_ttf-devel
```
Then, download and extract the zip file or clone the pacman repository.
Inside the pacman directory, run
```
./autogen.sh
./configure
make
make install
```

## License ##
Pacman is licensed under the terms of the GNU General Public License version 2 (or any later version).
