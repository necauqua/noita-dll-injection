const std = @import("std");
const win = @cImport({
    @cInclude("windows.h");
});

const payload = @import("payload.zig");

// cImport produces a variadic .x86_stdcall function pointer for FARPROC, which zig doesn't seem to like
const FARPROC = *opaque {};
extern "kernel32" fn GetProcAddress(hModule: win.HMODULE, lpProcName: win.LPCSTR) callconv(.{ .x86_stdcall = .{} }) FARPROC;

var original_dll: ?win.HMODULE = null;

pub fn DllMain(hModule: ?*anyopaque, dwReason: u32, lpReserved: ?*anyopaque) callconv(.winapi) win.BOOL {
    _ = hModule;
    _ = lpReserved;

    switch (dwReason) {
        win.DLL_PROCESS_ATTACH => {
            var systemPath: [win.MAX_PATH]u8 = undefined;

            const pathLen = win.GetSystemDirectoryA(&systemPath, systemPath.len);

            const suffix = "\\winmm.dll";
            @memcpy(systemPath[pathLen..], suffix);
            systemPath[pathLen + suffix.len] = 0;

            const dll = win.LoadLibraryA(systemPath[0 .. pathLen + suffix.len :0]) orelse {
                _ = win.MessageBoxA(null, "Original winmm.dll not found. Bad WINEDLLOVERRIDES on Linux?", "Noita DLL Injection Error", win.MB_OK);
                return win.FALSE;
            };
            original_dll = dll;

            for (function_names, 0..) |name, i| {
                function_pointers[i] = GetProcAddress(dll, name.ptr);
            }

            payload.run() catch |err| {
                var buf: [64]u8 = undefined;
                const msg = std.fmt.bufPrintZ(&buf, "The injection failed. Error code: {s}", .{@errorName(err)}) catch "The injection failed.";
                _ = win.MessageBoxA(null, msg, "Noita DLL Injection Error", win.MB_OK);
            };

            return win.TRUE;
        },
        win.DLL_PROCESS_DETACH => {
            if (original_dll) |dll| {
                _ = win.FreeLibrary(dll);
            }
        },
        else => {},
    }
    return win.TRUE;
}

var function_pointers = [_]?FARPROC{null} ** function_names.len;

// export all names as jmp trampolines to the corresponding pointer from function_pointers
comptime {
    for (function_names, 0..) |name, i| {
        const proxy = struct {
            fn proxy() callconv(.naked) noreturn {
                // "m" does not work in zig :(
                // it does some weird stack memory setup that breaks the perfect jump
                asm volatile ("jmp *%[ptr]"
                    :
                    : [ptr] "r" (function_pointers[i]),
                );
            }
        }.proxy;

        @export(&proxy, .{ .name = name });
    }
}

// since we have the nice comptime macro, trampoline literally every single winmm.dll function
// so it will work forever no matter what ^_^
const function_names = [_][]const u8{
    "CloseDriver",                  "DefDriverProc",        "DriverCallback",          "DrvGetModuleHandle",
    "GetDriverModuleHandle",        "NotifyCallbackData",   "OpenDriver",              "PlaySound",
    "PlaySoundA",                   "PlaySoundW",           "SendDriverMessage",       "WOW32DriverCallback",
    "WOW32ResolveMultiMediaHandle", "WOWAppExit",           "aux32Message",            "auxGetDevCapsA",
    "auxGetDevCapsW",               "auxGetNumDevs",        "auxGetVolume",            "auxOutMessage",
    "auxSetVolume",                 "joy32Message",         "joyConfigChanged",        "joyGetDevCapsA",
    "joyGetDevCapsW",               "joyGetNumDevs",        "joyGetPos",               "joyGetPosEx",
    "joyGetThreshold",              "joyReleaseCapture",    "joySetCapture",           "joySetThreshold",
    "mci32Message",                 "mciDriverNotify",      "mciDriverYield",          "mciExecute",
    "mciFreeCommandResource",       "mciGetCreatorTask",    "mciGetDeviceIDA",         "mciGetDeviceIDFromElementIDA",
    "mciGetDeviceIDFromElementIDW", "mciGetDeviceIDW",      "mciGetDriverData",        "mciGetErrorStringA",
    "mciGetErrorStringW",           "mciGetYieldProc",      "mciLoadCommandResource",  "mciSendCommandA",
    "mciSendCommandW",              "mciSendStringA",       "mciSendStringW",          "mciSetDriverData",
    "mciSetYieldProc",              "mid32Message",         "midiConnect",             "midiDisconnect",
    "midiInAddBuffer",              "midiInClose",          "midiInGetDevCapsA",       "midiInGetDevCapsW",
    "midiInGetErrorTextA",          "midiInGetErrorTextW",  "midiInGetID",             "midiInGetNumDevs",
    "midiInMessage",                "midiInOpen",           "midiInPrepareHeader",     "midiInReset",
    "midiInStart",                  "midiInStop",           "midiInUnprepareHeader",   "midiOutCacheDrumPatches",
    "midiOutCachePatches",          "midiOutClose",         "midiOutGetDevCapsA",      "midiOutGetDevCapsW",
    "midiOutGetErrorTextA",         "midiOutGetErrorTextW", "midiOutGetID",            "midiOutGetNumDevs",
    "midiOutGetVolume",             "midiOutLongMsg",       "midiOutMessage",          "midiOutOpen",
    "midiOutPrepareHeader",         "midiOutReset",         "midiOutSetVolume",        "midiOutShortMsg",
    "midiOutUnprepareHeader",       "midiStreamClose",      "midiStreamOpen",          "midiStreamOut",
    "midiStreamPause",              "midiStreamPosition",   "midiStreamProperty",      "midiStreamRestart",
    "midiStreamStop",               "mixerClose",           "mixerGetControlDetailsA", "mixerGetControlDetailsW",
    "mixerGetDevCapsA",             "mixerGetDevCapsW",     "mixerGetID",              "mixerGetLineControlsA",
    "mixerGetLineControlsW",        "mixerGetLineInfoA",    "mixerGetLineInfoW",       "mixerGetNumDevs",
    "mixerMessage",                 "mixerOpen",            "mixerSetControlDetails",  "mmDrvInstall",
    "mmGetCurrentTask",             "mmTaskBlock",          "mmTaskCreate",            "mmTaskSignal",
    "mmTaskYield",                  "mmioAdvance",          "mmioAscend",              "mmioClose",
    "mmioCreateChunk",              "mmioDescend",          "mmioFlush",               "mmioGetInfo",
    "mmioInstallIOProcA",           "mmioInstallIOProcW",   "mmioOpenA",               "mmioOpenW",
    "mmioRead",                     "mmioRenameA",          "mmioRenameW",             "mmioSeek",
    "mmioSendMessage",              "mmioSetBuffer",        "mmioSetInfo",             "mmioStringToFOURCCA",
    "mmioStringToFOURCCW",          "mmioWrite",            "mmsystemGetVersion",      "mod32Message",
    "mxd32Message",                 "sndPlaySoundA",        "sndPlaySoundW",           "tid32Message",
    "timeBeginPeriod",              "timeEndPeriod",        "timeGetDevCaps",          "timeGetSystemTime",
    "timeGetTime",                  "timeKillEvent",        "timeSetEvent",            "waveInAddBuffer",
    "waveInClose",                  "waveInGetDevCapsA",    "waveInGetDevCapsW",       "waveInGetErrorTextA",
    "waveInGetErrorTextW",          "waveInGetID",          "waveInGetNumDevs",        "waveInGetPosition",
    "waveInMessage",                "waveInOpen",           "waveInPrepareHeader",     "waveInReset",
    "waveInStart",                  "waveInStop",           "waveInUnprepareHeader",   "waveOutBreakLoop",
    "waveOutClose",                 "waveOutGetDevCapsA",   "waveOutGetDevCapsW",      "waveOutGetErrorTextA",
    "waveOutGetErrorTextW",         "waveOutGetID",         "waveOutGetNumDevs",       "waveOutGetPitch",
    "waveOutGetPlaybackRate",       "waveOutGetPosition",   "waveOutGetVolume",        "waveOutMessage",
    "waveOutOpen",                  "waveOutPause",         "waveOutPrepareHeader",    "waveOutReset",
    "waveOutRestart",               "waveOutSetPitch",      "waveOutSetPlaybackRate",  "waveOutSetVolume",
    "waveOutUnprepareHeader",       "waveOutWrite",         "wid32Message",            "wod32Message",
};
