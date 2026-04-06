# noita-hook

This is a Zig library helper for writing ASI mods for Noita.
ASI files are just DLLs that get loaded into the game by an ASI loader,
something like [Ultimate ASI Loader](https://github.com/ThirteenAG/Ultimate-ASI-Loader).

To use it, grab the 32-bit `winmm.dll` file from its releases page, and put it
next to the `noita.exe` file in its folder.

If using Steam, the easy way to find the game directory that contains
`noita.exe` is by right-clicking on the game in your library, then going to
"Manage" -> "Browse local files".

> [!NOTE]
> On Linux, due to the way Proton changes how DLLs are loaded, for this to work
> you need to set `WINEDLLOVERRIDES=winmm=n,b %command%` in the game launch
> options in Steam in addition to adding the DLL in the game folder.

This repository also contains three tiny ASI mods I wrote, in the `examples`
folder (you can also download them from the releases page).
To install them, put an .asi file in the `plugins` folder next to `noita.exe`
after installing ultimate asi loader (create the folder if it doesn't exist).

Those mods are:
- `allow-unsafe-workshop-mods.asi`:
  What it says on the tin - if someone _somehow_
  ([wink-wink](https://steamcommunity.com/sharedfiles/filedetails/?id=3504301317))
  managed to trick noita_dev.exe into uploading an unsafe mod to Steam Workshop,
  this mod disables the check that prevents unsafe mods installed from Steam
  Workshop from working.
- `fix-mod-restart.asi`:
  If you use the `-always_store_userdata_in_workdir` noita.exe CLI argument for
  modding or to otherwise have separate saves (for example my other project
  [noita-ts](https://github.com/necauqua/noita-ts) uses this), that argument is
  not preserved if you click the "Restart with mods enabled" button, which this
  patch fixes.
- `unsafe-mod-banners.asi`:
  Honestly this should be a vanilla feature - adds a red `[unsafe]` banner to
  unsafe mods in the modlist, it looks really cool.

## License
As with everything I do, this is licensed under the MIT, meaning you have to
copy the LICENSE file which has my name on top of it to use major parts of this
code.

But like eh there's nothing unique here, so at most just credit me lol.
