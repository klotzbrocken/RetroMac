# Beta reply — RetroMac 1.6.5

Hey — thank you again for the brilliant, detailed feedback. Several of the things you
ran into are fixed in this new build (1.6.5), and a couple of your ideas turned straight
into features. Quick rundown of what's new for you:

**Virtual camera turning itself off — fixed**
The switch was snapping back to OFF because activating the camera system-extension happens
asynchronously and there was no feedback while it worked. Now:
- The toggle stays ON while the extension activates, instead of looking like it switched
  itself off.
- If macOS still needs your approval, you get a clear prompt pointing you to
  System Settings → General → Login Items & Extensions → **Camera Extensions** — enable
  "RetroMac" there, then flip the switch again. (This is the step that's easy to miss —
  the Camera *privacy* toggle and the *extension* approval are two different switches.)
- If it needs a restart or fails, you now get a plain-language reason instead of silence.

**Multi-monitor — pick any of your 3 displays (fixed)**
Selecting a non-primary monitor now works. The stored display ID could go stale across
reboots/reconnects, which left only the main HDMI display rendering; it now resolves to
the right screen (with a safe fallback) so Monitor 2 and 3 theme correctly.

**Wallpaper restored per monitor (improved)**
Leaving a theme now restores each display's previous wallpaper more reliably, with
per-screen logging. One honest caveat: if a monitor was using a macOS *dynamic/aerial*
wallpaper, that specific type can't always be put back by the system API and may fall back
to a static image — if you still see one reset, let me know which wallpaper type it was and
I'll dig in with the new logs.

**Retro TV skins**
The TV player is in the app today. Different vintage TV sets (wood-grain console, portable,
etc.) are now firmly on the roadmap — totally agree it'd be very cool.

**Snow Leopard intro idea**
Love it — playing that classic intro when you switch to the Snow Leopard theme, ideally
inside the TV player with an iMac skin, is on the list. Great call.

**Bonus: Maik's Favourite is now the default — and more playful**
The animated Pac-Man theme ("Maik's Favourite") is now the default dock theme. A few new
touches:
- Cherries appear sporadically; eat one and Pac-Man powers up and hunts the ghosts.
- Hovering a dock icon still releases a ghost (max 2) — and now the icon also acts as a
  **barrier**: Pac-Man or a ghost running into it turns around, so you can actually steer
  the chase with your mouse.

Grab the attached 1.6.5 DMG (signed & notarized). Keep the feedback coming — it's shaping
the app directly. 🙏🚀
