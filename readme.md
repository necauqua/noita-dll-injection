# noita-dll-injection

This is a simple instance of Noita engine modding through DLL injection.

This mod patches the game to disable the check that disallows enabling unsafe
mods added through Steam Workshop.

It's written in a way that should be unlikely to break if the game happens to
receive an update. Also it obviously only works with the Steam version of the
game.

To use it, download the `winmm.dll` file from the
[releases](https://github.com/necauqua/noita-dll-proxy/releases) page and place
it in the game directory, where the `noita.exe` file is located.

To easily find the directory, in Steam right-click on the game in your library,
go to "Manage" -> "Browse local files". This will open the correct folder, just
drag the DLL over there.

> [!NOTE]
> On Linux, due to the way Proton changes how DLLs are loaded, for this to work
> you need to set `WINEDLLOVERRIDES=winmm=n,b %command%` in the game launch
> options in Steam in addition to adding the DLL in the game folder.

## How it works
DLL injection is a simple technique where you "trick" an executable into
loading a custom DLL with no extra configuration or file editing.

Basically, when an executable loads a DLL, it searches for it in several places
with different precedence. What is important for our purpose is that it looks
for them in the working directory before the system directories.

The idea is then to make a custom DLL named as some system DLL that the
executable loads and place it in the working directory of the executable.

It has to export the functions that the executable expects from the system
library, and call the corresponding functions from the original system DLL so
that the correct behaviour is preserved - this is called "DLL proxying".

And since this is our custom DLL - that we made! - in can run any code in the
address space of the executable when its `DllMain` entry point is called.

We use the `winmm.dll` system library (the Windows Multimedia API) as a target
for DLL proxying, because Noita happends to load it, it's a common target for
this.

## License
As with everything I do, this is licensed under the MIT, meaning you have to
copy the LICENSE file which has my name on top of it to use major parts of this
code.

But like eh there's nothing unique here, so at most just credit me lol.
