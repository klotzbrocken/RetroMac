# Changelog

All notable changes to RetroMac are documented here. For older releases and the
downloadable DMGs, see the [GitHub Releases](https://github.com/klotzbrocken/RetroMac/releases).

## 2.8.7

- **New theme: System 7.1 (authentic).** System 7.1 as a colour Mac showed it, at the
  Monitors control panel's "256": every icon RetroMac draws under the theme — the desktop, the
  Apple menu and its submenus, the Application menu, the Applications window, the Control
  Strip — is resampled to the pixels it is shown at and snapped to the Mac's standard 8-bit
  colour table (the 6 × 6 × 6 cube and the red, green, blue and grey ramps), with the hard
  edge of a 1-bit mask; the menu bar wears the rainbow apple (a manifest says
  `menuBar.palette: "mac256"`). The resolution and the desktop are the ones you have: the
  desktop pattern tiles across whatever the screen is, and windows keep their places.
  The **Control Strip** is System 7.5's on a colour Mac, pixel for pixel: every piece is the
  original's own art, taken from a screenshot of the real strip and snapped to the 256-colour
  table — the close box, the scroll arrows (sunk in and grey with nothing to scroll to, raised
  and black when there is), the tab with its grip, and the five modules it carried: AppleTalk
  Switch, File Sharing (crossed out in red while it is off), Monitor Bit Depth, Monitor
  Resolution and Sound Volume, whose waves follow the volume. A theme picks its own set with
  `dock.stripModules`. Sizes and behaviour are Mac OS 9 (authentic)'s: the tab rolls it out
  and in and sets how much shows, Option-drag rearranges the modules or moves the strip.
  The **desktop** has Macintosh HD at the top right, the Trash at the bottom right whatever
  the screen's size (a negative `gridY` counts from the bottom now), the Applications folder,
  and one icon per mounted volume under the hard disk (`type: "volumes"`); a selected name
  inverts rather than taking the accent colour. The **menu bar** has System 7.1's icon-only
  Application menu (`menuBar.applicationMenuIconOnly`), the Balloon Help `?` balloon
  (`menuBar.balloonHelp`) and the Apple menu of the day, with Mac OS 9 (authentic)'s pictures
  in the 256 colours. Windows use their own `system7` chrome, measured pixel for pixel
  from System 7.1 running in an emulator: a 19 px title bar with six #777777 stripes on
  #EEEEEE between a #CCCCFF light edge and a #9999CC shadow, the close box left and the zoom
  box right sunk into it in #333366 and #AAAAAA, the 1 px black frame with its 1 px shadow, and
  scroll bars with #9999CC arrows in raised #DDDDDD boxes, a dotted track and the fixed 16 px
  scroll box with its lavender grip; an inactive window's bar is white with a grey title. The
  title bars over real windows, the widget windows, the TV window (its picture in colour
  now), the Applications window and the theme's Read Me all wear it. The
  menus open at once: the Apple menu's submenus (the Applications folder, Control Panels,
  Favorites and the three recent lists) are read when they open rather than when the menu is
  built, every picture is converted once and kept, and the conversion works on the raw bytes
  through a 32 768-entry lookup table. Battery reads slowly, volume and network on their
  events.

- **Starfield Simulation.** The Windows 2000 screen saver, for every theme: white squares
  streaming out of the centre of a black screen, drawn as the original drew them (the far
  plane, the star sizes, the 20 ticks a second, the speed ramp and the integer arithmetic
  follow Ilya Kalimulin's disassembly of `ssstars.scr`, MIT — LEGAL.md). In the screensaver
  picker of every theme, and as a real macOS `.saver` module with the others.

- **The Apple cover stays off without Accessibility.** The retro Apple in the menu bar is
  placed by asking the menu bar where the Apple is, which takes the Accessibility permission;
  without it the cover could only guess and sat beside the real Apple or half over the first
  menu. Now it is not shown at all, and the Apple-logo picker under Desktop is greyed with the
  reason. In the same spirit the Shader Presets menu greys every full shader (and Surprise)
  while Screen Recording is missing and says why, leaving the Lite presets, and everything
  in the wallpaper scope, which never captures the screen.

- **Settings ▸ General ▸ "macOS defaults".** The emergency exit: turns the theme and the
  shader off and puts the system back whether or not RetroMac remembers changing it — the
  cursors from the factory capture, every Finder, window-corner and animation default a
  theme may write (deleted, so macOS uses its own), the Dock (shown, bottom, Genie), the menu
  bar, the desktop icons, the wallpaper, the appearance and the Terminal profile. Confirmed
  first, since it also resets those defaults where the user had set them.

- **A leftover square-corner setting is cleaned up.** The title bars' corner value
  (`NSConvolutionOverride1` = 0.5, the smallest the key takes) could outlive RetroMac: a
  session killed outright never restored it, and a second RetroMac running beside it (a
  development build next to the release) snapshotted that 0.5 as the user's "original" and
  put it back on every restore — every app then opened with square corners, theme or no
  theme. Nobody sets 0.5 by hand, so at launch an untracked 0.5 is deleted (and the Finder
  refreshed), and a 0.5 found while snapshotting is recorded as "unset".

- **The Apple cover takes the first click.** A theme's own Apple menu did not open while
  another app was in front: the cover was a plain window, so the first click only activated
  RetroMac and was swallowed, and a cover made before the theme came up ignored the mouse
  until a later refresh. It is a non-activating panel now that accepts the first click, and
  whether it takes clicks is settled the moment the theme changes.

- **Fix: a click on a background window's themed title bar brings that window forward at
  once.** The window is raised first and its app activated after — through Accessibility, since
  macOS 14 lets an app in the background activate another only that way — so it is the clicked
  window that comes to the front and not whichever of the app's windows was frontmost, and none
  of it runs on the main thread any more (a browser slow to answer Accessibility put up the
  spinning cursor). Dragging a window by its bar starts afresh from that window on every press
  and sets the position in the background, coalesced: a mouse-up that never arrived no longer
  leaves a stale starting point that threw the next drag — of this window or another — off.
- **Fix: desktop names that wrap to two lines get a plate that fits.** The plate and the
  selection were sized from font metrics, which a pixel font understates: "Time Machine" got
  a plate the label's full width, "Macintosh HD" one line of plate and a second line cut in
  half. They are measured by the label's own cell now, as it wraps, and the label is as tall
  as its two lines.

- **Fix: the themed dock gives way to the macOS Dock when auto-hide is switched off.** RetroMac
  keeps the real Dock out of sight by setting it to hide with an endless delay; switching
  "Automatically hide and show the Dock" off in System Settings (or ⌥⌘D) brought it back over
  the Snow Leopard or Mountain Lion dock, which then only showed while auto-hide was on. RetroMac
  now notices within two seconds, takes the choice for the themed dock (it stays put), hands it
  to macOS when it lets the real Dock go, and hides the real Dock again.
- **Fix: the status menu names the theme you chose in Settings.** "Themes ▸ …" kept the
  previous theme until something else rebuilt the menu.

## 2.8.6

- **New theme: Mac OS 9 (authentic).** The desktop as it was, next to "Mac OS 9.2 Classic",
  which stays as it is. No dock: programs open from the Finder, and the **Application
  menu** at the right end of the menu bar (the front app's icon; Hide, Hide Others, Show All,
  the running apps with a tick at the front one) switches between them. The **Control Strip**
  along the bottom-left edge holds the system, not programs: AppleTalk turned network
  connection, File Sharing, colour depth, monitor resolution (with the real modes, and a
  15-second "keep or revert" after a switch, as the Monitors control panel had), sound volume,
  the battery on a portable, video mirroring with a second display. The tab at the screen edge
  collapses the strip and drags it up and down; the size box at the other end sets how much
  shows; the arrows scroll the rest. Position, width and collapse are remembered. The desktop
  holds Macintosh HD, Applications and the Trash. The Apple cover opens the **Apple menu** of
  the day — About This Computer, Applications, Apple System Profiler, Calculator, Chooser,
  Control Panels, Favorites, Network Browser, Recent Applications, Recent Documents, Recent
  Servers, Sherlock 2, Stickies — each pointed at what macOS has now, the recent lists read
  from the Finder's own. The Application menu shows the theme's icon for apps it knows and
  the app's name beside it, as Mac OS 8.5 onwards did; an app picked there comes to the
  front with every one of its windows, and one whose windows are all minimised gets its
  first back. A window minimised under this theme — the bar's box or ⌘M — does not shrink
  into the corner where the hidden Dock is: its picture, bar and all, zooms away to the top
  of the desktop and is gone, the zoom rectangles of the day; a still of what lies under it
  hides the real minimise meanwhile. The Platinum title bar over real
  windows is drawn line for line like the widget windows' bar, in every state, and stands a
  point out on each side, on the hairline macOS draws round every window, so its frame is
  flush with the window as seen (with the window border on, the border covers that line and
  the bar is exactly the window's width); the theme readme's bar is Platinum too. The menus themselves — the Apple menu, the Application menu,
  the Control Strip modules' — are drawn by RetroMac in Platinum (#DADADA, Charcoal, the blue
  highlight, fly-out submenus that scroll with arrows when they outgrow the screen), with the
  theme's own pictures on the first level; this macOS shows no images in an NSMenu at all. The
  strip goes under the Live Wallpaper Plus shader like the dock does, at twice its 1× size,
  on the bottom edge. A module with one thing to do (network, sharing, the battery: open its
  settings) does it on the click; only a choice gets a menu. The sound module stands up the
  slider of its day: press, drag, let go — Platinum track, seven ticks, the round-shouldered
  knob — not the Windows tray's popup. Four more modules from the original strip: Keychain
  (lock every keychain; open Passwords), Media Bay (the removable volumes, each with Eject),
  Printer Selector (the default printer, the others to pick) and SoundSource (output and input
  device); Video Mirroring is always on the strip and says when it lacks a second display.
  Option- or Control-drag rearranges a module or moves the whole strip to either edge and up
  and down it, as the original did; the order is remembered. A second click on a module closes
  its open menu. The strip is 36 pt tall, one and a half times its 1× size — in step with the
  desktop icons' labels and the menus — and Settings ▸ Dock ▸ Control Strip has Small (24 pt)
  and Large (48 pt) as well; its tab
  rolls it out and in over a third of a second, the modules sliding from behind the tab, as
  the strip of the Classic theme does.
  The modules end in the small black triangle the originals had, the scroll arrows are the
  hollow Platinum arrows, and the keychain, colour-depth, printer and speaker modules wear
  the era's pictures (`icons/strip-<module>.png`; a module without one draws its own). The
  menu-bar band on the wallpaper is flat #DDDDDD. The Platinum menus and the Application
  menu are set in ChiKareGo2 (Giles Booth, CC BY), Chicago 12 as a bitmap face; the desktop
  icons are labelled in Pixel Operator (Jayvee Enaguas, CC0) on a `#CFCFE1` plate, through the
  new `desktopLabel` manifest key, with air between icon and plate. Both faces ship in
  Resources/Fonts with their licences. The Platinum menus scroll with the trackpad or wheel,
  not only by their arrows, and a second click on the Apple cover closes the Apple menu.
  Theme authors: `dockStyle: "controlStripModules"`, `menuBar.applicationMenu` and
  `menuBar.appleMenu` in docs/THEMES.md. Settings ▸ Themes was cut off 9 pt at both
  sides under this theme (a row with two segmented controls and a button outgrew the pane
  and the whole view with it); the size picker has its own row now.

- **Experiment: title bars in theme style.** Under Themes ▸ System integration, next to the
  window borders, when Mac OS 9 or Windows XP is selected: a Platinum or Luna title bar over
  every real window. It is RetroMac's own panel above the window, not a change to the app, and
  its controls drive the real window through Accessibility: close, minimise (the WindowShade
  box minimises), zoom the way the era did (to the screen and back, stopping at the taskbar;
  never native full screen), and dragging where the traffic lights used to be. Everywhere else
  the bar lets the mouse through, so the native drag and double-click keep working. The bar
  that belongs to the front window draws active, the others draw inactive. The windows are
  square while it is on: macOS is asked to stop rounding them (the same corner setting the
  "Classic Finder" tweaks use, at its smallest value, snapshotted and put back), which every
  app picks up when it is next opened. Apps can be left alone ("Leave these apps alone", from the
  running apps or any app). A closed window takes its bar with it at once, and a dragged
  window's bar keeps up. Known limits: a toolbar that shares the title bar (Safari, Finder)
  loses its top edge under the strip, and a window the size of the screen gets no bar.

- **The Aqua dock's magnification stopped reading from disk.** The name label above the
  magnified icon looked the app's name up on every mouse move — the app bundle's localized
  Info.plist for a pinned app, two LaunchServices round trips for a running one — which was a
  quarter of the main thread's time while the pointer crossed the dock. Names are kept now.
  The title-bar overlay no longer re-orders its panels every three seconds either, only when
  the z-order actually changed.

- **The dock stutters no more while the title bars or lights are on.** The overlay watched the
  pointer through a global mouse monitor, to hand its panels the mouse when it reached a
  control. With such a monitor installed, the WindowServer delivered the dock's own mouse
  moves in bursts (thirty a second with gaps of up to 700 ms instead of a steady stream) from
  the first change of front application on, which is what made the magnification judder.
  The overlay now asks where the pointer is 25 times a second instead, which the dock does
  not notice. The dock's own auto-hide watched the pointer the same way and juddered the same
  way once it was revealed; it polls now too. Measured with the dock's new cadence log
  (`RETROMAC_DOCK_STATS=1`).

- **The "Classic window corners" hint no longer traps the boot screen.** With the title bars
  on, the one-time hint ran as a modal alert in the middle of the switch: it sat under the
  boot cover where nobody could see it, and its modal run loop starved the timer that takes
  the cover down, so the Windows Me and Mac OS 9 boot animations looped until the unseen OK
  was found. The hint now waits until the switch has settled and the boot screen is gone, and
  only appears if the corners are still wanted by then (a launch turns the bars on, off and on
  again while it recovers, and used to fire it prematurely).

- **The lights leave with the window when its own minimise button is pressed.** Three
  things kept them on the shrinking picture: the WindowServer's minimise event arrives once
  the genie has finished (measured: nothing earlier is sent, for any window); the press
  itself blocked RetroMac's main thread until the app's animation was over, so the panel's
  disappearance was never committed in time; and a click in the 40 ms before the hover poll
  made the panel hot went to the real light underneath, minimising natively with our lights
  still on top. Now every panel takes the mouse from the start (the poll is gone; the view's
  own tracking area does the hover), a close or minimise through the overlay hides the panel
  at once and presses the real button off the main thread, and the window is left alone for
  a second so no fresh measurement puts the lights back mid-genie; the window border goes
  with them. Cmd-M and the Dock still have only the late event: there the lights and the
  frame stay for the genie's half second.

- **Title bars, third audit, and the lights leave the window corners alone.** The lights
  styles no longer write the global corner default (they asked for 5 pt, Snow Leopard's
  rounding): it is a value every app reads at launch and it puts a mask on the app's windows,
  under which Webex showed every participant grey while its own camera preview ran. The bars
  keep it (square corners are their point) and the Settings row says what that can do to a
  video app started meanwhile. Accessibility reads (the lights' positions, titles) run on a
  queue of their own now, so an app that does not answer costs its timeout there and not in
  the dock's magnification; the user's own actions stay where they were. A title fetched
  through Accessibility is asked for again when its window comes forward (the earlier attempt
  listened to an event that names no window). A theme change within one style (95 → 98 → Me,
  a Plus! scheme) redraws the bars at once. Two windows resized within half a second are both
  re-measured. A late photograph cannot land on a bar rebuilt by a theme switch. A live resize
  updates that one border instead of the whole list. Aero's glass follows the bar's rounded
  corners and the frame's sides stop under them. A window moved or shortened to make room for
  its bar goes back when the bars go off, unless the user has moved it since.

- **Title bars, second audit.** A dictionary of bundle identifiers was written from the
  window-list thread and pruned on the main thread at once (a crash waiting for an app to quit
  mid-sync); it is main-thread only now. A window without buttons was measured again every
  second because dropping its overlay also dropped its retry schedule; the schedule survives
  (1, 2, 4 … 30 s). A bar takes the mouse from the moment it appears, so a window opening under
  a resting pointer no longer lets the first click through to whatever lies behind; the lights
  panel is routed right after it appears or moves. The patch over the real lights only shows
  the newest photograph, and when a capture fails it stays out of the way (the real lights
  remain usable) instead of catching clicks while showing nothing. An excluded app's window
  border no longer frames an empty strip above it. The patch is re-ordered only when the
  order changed, a live resize re-syncs the borders once per turn, and a bar buried under its
  own window (Chrome's new tab) is detected without re-ordering everything every second. A
  window pushed down to make room for its bar is shortened when it would end under the
  taskbar, and never touched while a mouse button is down. Titles read through Accessibility
  are asked for again when the window comes forward; the lights are re-measured once a resize
  has settled. A zoom the app refused leaves no restore state behind. The permission going away
  stops the feature instead of leaving dead buttons. And the Luna and Aero bars round their top
  corners now that they sit above the window.

- **Chrome's tabs no longer bury the lights.** Opening a tab raises Chrome's window over the
  Aqua lights without the WindowServer reporting a reorder, and the overlay's own check for a
  changed z-order looked only at other apps' windows, so nothing put them back until the
  window moved. The check now covers RetroMac's own panels too; the lights return within a second.

- **The menu-bar Apple logo stopped blinking.** Every screen-parameter change (a full-screen
  window covering the menu bar, a boot screen, a crash) and every theme switch tore the logo's
  windows down and made new ones, several times per switch; it now keeps its windows and only
  moves them, and a burst of update requests is answered once.

- **A crash on a theme that keeps the menu bar no longer ends before it begins.** Covering the
  visible menu bar with the crash's full-screen windows made AppKit report changed screen
  parameters a moment later, which the crash took for a display being unplugged and aborted
  on: on Mac OS 9 (and any theme with the menu bar showing) the bomb never appeared. Screen
  changes in the first seconds are now ignored, as focus changes already were.

- **The boot screen can always be clicked away, and a stuck switch cannot lock the Mac.**
  The click used to run the waiting theme switch first and take the cover down after, so a
  click sat through the whole switch — and a switch that blocked (an Apple event to a Finder
  the theme's own tweaks were relaunching can wait two minutes) left a full-screen key window
  over everything, with no Escape. Now the cover comes down first; a watchdog on another thread
  removes it through the WindowServer if the main thread stops answering under it for four
  seconds; and every Apple event RetroMac sends gives up after four seconds instead of two
  minutes.

- **Traffic lights keep up with a dragged window.** The lights were re-measured through
  Accessibility for a window's first seconds, and an app being dragged answers slowly — nine
  round trips at up to half a second each was the pause before the orbs caught up. They are
  measured once now, against the corner Accessibility reports in the same breath.

- **Windows 95, 98 and Me: the caption is the size of the theme's own windows** (22 pt, 20×18
  buttons), not the 18 pt of a 96-dpi screen next to them.

- **Under the Mac OS X and Snow Leopard lights the windows round their corners the era's way**
  (about 5 pt), through the same corner setting the bars use to square them, for every app
  opened after the switch.

- **The title bar sits above the window now, not on it, for every Windows and Mac theme.**
  System 6 (racing stripes, close and zoom boxes), Mac OS 9 (Platinum), Windows 3.1 (the
  system-menu box, ▼ and ▲), Windows 95, 98 and Me (the caption in the theme's own colour
  scheme, three bevel buttons), Windows XP (Luna) and Windows 7 (real Aero glass, the desktop
  blurred behind the bar). Mac OS X, Mountain Lion and Snow Leopard keep the lights-only mode.
  The bar is added on top of the real window, outside it: the real title bar and
  its toolbar stay whole and clickable (Finder, Notes, Safari, Mail included), the bar is the
  window's own to drag and double-click, and the frame goes round both. What is left of the
  real bar is its three lights, and they disappear under a patch that wears the bar's own
  colour, photographed off the screen beside them, so light, dark and inactive all match. A
  window with no room above it is moved down by the bar's height; a zoomed window leaves the
  bar its room.
  The frame is 3 pt on Windows XP instead of 4, has no edge of its own above a Windows bar
  (the caption is the top of the frame, as it was), and paints nothing into the corners: the
  windows are square, and the few that were open before stay rounded until they are reopened.

- **Title bars, hardened after review.** Every Accessibility request this process makes now
  gives up after half a second instead of six, so a hung app no longer hangs RetroMac (checked
  with a frozen TextEdit: RetroMac answered in 50 ms). Where a window keeps its lights lower
  (Finder, Notes, Safari) the strip grows to cover them. The bar needs the
  Accessibility permission and says so in Settings; a click on a window that is not in front
  brings it there first; the dead zone over the real lights is measured per window; a long
  Platinum title is shortened in the middle instead of running over the boxes; a maximised
  Luna window shows Restore, an inactive one pales its buttons; zoom remembers what the app
  actually allowed, so a window with a size limit restores too; windows the size of their own
  screen are told apart on a second monitor; titles are cached and app icons too. And it
  stays off the main thread's back: the window list is fetched in the background, the
  overlays are re-ordered on the WindowServer's events instead of every pass, and the
  safety-net poll runs once a second — 1.8 ms of main-thread work per second instead of 15,
  which is what stuttered the Snow Leopard dock's magnification.

- **Experiment: traffic lights in theme style.** The same switch on Mac OS X and Snow Leopard
  covers only the three lights: Snow Leopard's glossy orbs from the theme's own artwork, or
  Aqua gems for Mac OS X, at the exact spots the real lights sit in each window, with the ×,
  − and + on hover. Nothing else about the title bar changes, so toolbars keep their top edge.

## 2.8.5

- **Paint, Solitaire, Minesweeper, Internet Explorer and 3D Pinball open again.** The site
  that hosted these 98.js programs (bored-win98.pisaucer.com) went off the air in September;
  its DNS name is gone, and the earlier github.io address still redirects into that void. The
  five Windows themes now load them from 98.js.org, the upstream project's own site, and a
  theme or desktop layout saved with an old address is rewritten on open. The native
  Save/Print bridge is trusted for the new host only.

- **"Do not turn off your computer."** Two boot failures more: Windows XP installing update 3
  of 7 at shutdown, with the green Luna bar, and Windows 7 configuring updates at the next start,
  counting to 35% and staying there, and half the time giving up ("Failure configuring Windows
  updates. Reverting changes."). Like every boot failure they run on their own clock and end in
  the boot screen; Esc still ends everything.

- **The taskbar works without the Accessibility permission.** Until now the Windows taskbars
  showed no task buttons at all without it, and the app put up the system permission dialog
  at every start. Now they show one button per running program instead of one per window,
  clicking the active one hides the program the way minimising did, and a small caution sign at
  the left of the buttons says why and asks for the permission with one click. The system
  dialog at launch is gone; the Setup Assistant and Settings ▸ General still offer it.

- **`minAppVersion` in theme.json.** A theme can say which RetroMac it needs; an older build
  skips it with a line in the log rather than loading half of it. Compared numerically, so 2.10
  is newer than 2.9.

- **Documentation.** `docs/THEMES.md` describes the theme bundle, every manifest key, the
  desktop icon types and how to test a theme. `LEGAL.md` says what in the app was written for
  it, what is other people's free software, and what is the original artwork of the companies
  whose desktops it recreates, and whom to write to about any of it. The README shows the app
  instead of describing it: a hero, a tour, a gallery, and the download link at the top.

## 2.8.4

- **A smaller download.** The release binary is stripped (its symbols go to a dSYM next to
  the bundle), the Warcraft maps that came unpacked are gzipped like the rest, and the three
  Windows 7 wallpapers and Mac OS 9's poppy are re-encoded at a sane JPEG quality. About 15 MB
  less in the app, no visible change.
- **Settings, tidied.** One home per setting: the per-theme shader switch and preset are under
  Shader ▸ When only; wallpaper, desktop-icon size and the menu bar (tint and the Apple logo)
  under Desktop only; "hide the menu bar / desktop icons while the shader is on" under Shader ▸
  Where, next to the scope they belong to; the Setup Assistant under General only; permissions
  under General only, with Health Check left to what this Mac can do. The thirty-row "Behavior"
  card on Themes is four cards that say what they hold — Behaviour, Dock, the theme's extras,
  System integration. Screensaver, Games and Health Check use the same cards as every other tab
  instead of a system form. The hints that ran to six or eight lines are one line again. A
  wide control — a three-way segmented picker, a slider with its value, a text field with a
  button — now sits under its label instead of drawing over the hint, which is how the Live
  Wallpaper scope picker came to be unreadable. Switching "Show theme widgets" or a Windows
  tray messenger applies at once instead of at the next theme change. Three hundred lines of
  unreachable settings code are gone. `docs/SETTINGS.md` describes the window and its rules.

- **Windows 95 and 98: the seventeen pattern wallpapers.** Black Thatch, Blue Rivets, Bubbles,
  Carved Stone, Circles, Forest, Gold Weave, Houndstooth, Metal Links, Pinstripe, Red Blocks,
  Sandstone, Stitches, Straw Mat, Tiles, Triangles and Waves, under Change Wallpaper, each
  tiled edge to edge the way the originals were rather than stretched. A wallpaper option can
  now be tiled on its own, next to a photograph that is not.
- **Windows 95 has its hourglass.** Its own cursor set: the Retrosmart arrows with the real
  Windows 95 wait cursor.
- **Snow Leopard and Mountain Lion swap the pointer**, using the Mac OS X set; the Aqua arrow
  did not change between 10.0 and 10.8.
- **Mountain Lion has a boot screen**, the same as Snow Leopard's.
- **New icons:** Reminders on Snow Leopard; Word, Excel and PowerPoint on Mac OS X.

- **Windows 95 and Windows Me swap the pointer too.** Both kept the macOS cursor; they now use
  the same black-arrow set Windows 3.1 uses, which is what those desktops looked like. Windows 98
  is unchanged: the system pointer by default, the Plus! sets with their schemes.

- **Lite shaders cover every screen.** The Lite presets drew one window across the union of
  all displays. With an external 1x monitor as the main display next to the 2x built-in, AppKit
  handed that window to the built-in's scale and a band of the external screen was left without
  the effect. There is now one Lite window per screen, in that screen's own scale, rebuilt when
  a display is plugged in or out — the same shape the full shaders and the wallpaper shader have
  always had.

- **Retro Crashes: more of the period.** Twenty-six new scenes, in three kinds.

  *More failures.* "The instruction at 0x… referenced memory at 0x…" for XP and 7; the System
  Shutdown dialog of the summer of 2003, counting down from 59 with no button, which restarts the
  machine when it reaches zero; Dr. Watson; "It's now safe to turn off your computer", in
  orange; the floppy that was not there ("A:\ is not accessible", Retry, the drive hunting,
  Retry again); the scratched CD ("Data error (cyclic redundancy check)"); and on the Mac, "This
  disk is unreadable by this Computer", where Initialize is the mistake and the initialising
  fails. XP's Stop error now has a sequel: a little while after the machine comes back, it asks
  whether Microsoft may hear about it.

  *The Iomega Zip.* The Windows 95, 98, Me and XP desktops have a Zip drive on them now. Open
  it and the drive starts clicking: the click of death, synthesised like the hard disk, a
  run-out and a knock every half second. Windows reports the only thing it knows ("D:\ is not
  accessible", or on XP "The disk in drive D is not formatted"), and Retry makes it click again.
  It never happens on its own — only when you open the drive — and it is the one crash that is
  not in the random draw.

  *The machine not coming back.* After "Restart", sometimes the boot fails first: "Non-System
  disk or disk error", "NTLDR is missing", "BOOTMGR is missing", "S.M.A.R.T. Status BAD", the
  full-screen ScanDisk that Windows 9x ran after every unclean shutdown (with the bar that stalls
  somewhere in the middle), CHKDSK with its ten seconds to skip, the Sad Mac, the blinking
  question-mark folder, the prohibitory sign. Any key moves the boot along; so does waiting. A
  switch turns them off.

  *Moments.* Not a crash: the beach ball, the wristwatch, the hourglass, Windows 7's busy ring,
  CGA snow, the palette going for a beat, the picture losing sync and rolling before it locks
  with a click, the monitor's relay switching modes. A few seconds, no build-up, no error, and
  they pass. On their own clock — about three times as often as the failures at the same
  setting, with no daily limit — and their own switch.

  A text-mode screen now fills the display — 16:9 edge to edge by default, or 4:3 at full
  height from a new picker under Picture — instead of sitting in a black frame at whole-pixel
  size. A blue screen was the whole screen.

  "Crash Now" — the flyout button, the menu entry, "Surprise me" — now walks through the
  era: every failure, boot failure and moment once, in a shuffled order, then a fresh shuffle,
  never the same one twice in a row. Pressing it to see them all shows them all. The crashes
  that happen by themselves keep their weighted draw, and a boot failure on its own still only
  follows a restart.

  Every scene is in the settings list with its own Show button and its own toggle. Text screens
  gained a blinking cursor, progress bars and countdowns; dialogs gained a clock and a button
  that goes on to the next stage instead of closing. The watchdog now sizes itself to the scene
  it is watching rather than to a flat minute, so the countdown can run its course. Program and
  file names on the new screens are RetroMac's own where they can be, so nobody learns anything
  false about their machine.

  Without Screen Recording there is no still to freeze, and the windowed errors used to land
  on a black screen. They now land on the live desktop: not frozen, but yours. Text screens and
  the blackout before the boot screen stay black, as they were.

  Two fixes on the way: an interrupted Explorer restart now brings the desktop icons back, and
  the liveness check no longer ends an Explorer restart after two seconds for having no window —
  it has no window on purpose.

- **Live Wallpaper can now cover the whole desktop, not just the picture.** A new switch under
  Settings > Desktop runs the selected shader over the desktop picture, RetroMac's own desktop
  icons, the retro dock and an open start menu in ONE pass, so the scanlines run through all of
  them instead of restarting in each. Application windows are never touched. Getting one pass to
  span them meant putting the dock and the start menu into the band below the application windows
  while the mode runs, which is the visible cost: the retro taskbar is not on top while this is
  on. The effect also runs at the display's frame rate rather than the usual 30, because it now
  carries the dock's own magnification, and five frames of a 0.18 second animation looked exactly
  as stepped as that sounds.

- **The status menu lost four things it did not need.** "Apply to Full Screen" is gone, since that
  is what the effect does unless told otherwise, and "Apply to Window" is a switch instead of a
  second line with a tick on it. Window borders moved to Settings > Themes, "About This Theme"
  left the menu and stays on its desktop icon, and the floating launcher button became an icon in
  the menu's header next to Retro Mode, where it reads as a way back into RetroMac rather than as
  an afterthought under the setup assistant.

- **Mac OS 6 and 9 crash alerts: the text lines up, and every alert has an icon.** The fault line
  carried eight hard-coded spaces to indent it, which is an arbitrary width in a proportional face
  and left it standing out of line with the sentences above and below. All lines now share the one
  left margin the renderer already had, with a blank line where the original put a gap. And the
  "application has unexpectedly quit" alerts drew no icon at all while the layout still reserved
  the space for one, so they looked like the artwork had failed to load; they take the caution
  triangle now, drawn rather than bundled, in one bit for System 6 and in Platinum for Mac OS 9.

- **Windows 95/98/Me: the calculator's top strip was narrower than the rest of the window.** The
  title and menu bars were inset three pixels a side while the body beneath them spans the full
  window and paints over the frame, so the top sat four pixels narrower than everything under it.
  All three now share one width.

- **Windows Me folder and TV windows lose the navigation toolbar and the address bar**, and the
  web-view panel down the left gets the real banner artwork instead of the gradient standing in
  for it. What makes a Me window read as Me is that panel, not the buttons above it. The File and
  Window menu bar takes the theme's own face colour; it was the one grey surface the scheme
  recolouring had missed.

- **Office icons for Windows Me and XP.** Word, Excel, PowerPoint and Outlook in their 2000-03
  artwork, at each theme's own icon size. Outlook had no mapping in any theme before.

- **Windows 98 quick launch:** the Explorer and MS-DOS icons corrected in the same way Windows Me
  got them, and the messenger tile is ICQ.

- **Retro Crashes is on the Get More page.** It was gated behind the licence, wired to the unlock
  screen and listed as a paid feature everywhere except the one page the Setup Assistant shows to
  ask for the purchase. A test now checks that every paid feature is named there, and that the
  page sells nothing that is not actually gated.

- **The TV channel list gets a clean-out and six new channels.** Vevo's four streams had gone
  dead at their old addresses; they come back on working ones as VEVO 90s, VEVO 80s and VEVO 2K,
  joined by XITE 90s Throwback and XITE 80s Flashback in the slots the dead 90s and 80s channels
  held. Vevo Retro Rock has no successor and is gone. New alongside them: Totally Turtles, RetroTV
  and The Addams Family.

  Existing channel lists are updated too, not just fresh installs. The swap matches on the stream
  URL rather than the name, so it keeps each channel where it was along with the CRT preset chosen
  for it, leaves a channel alone if you had already pointed it somewhere else, and never brings
  back one you removed.

- **The muted tray speaker is visible again.** Muting drew the same grey speaker at 40% opacity,
  which works for a colourful icon and fails completely for this one: the speaker is mid-grey and
  so is the taskbar under it, so "muted" read as a half-erased icon rather than as a state. It now
  stays at full strength and takes a red prohibition sign over it — red being the one colour a
  Windows taskbar does not otherwise use, which is why it still reads at fourteen points. And the
  volume slider now tells the taskbar when it changes something: it never did, so muting from the
  popup left the tray showing the old state until an unrelated redraw came along.

- **The Windows 95/98/Me tray has one rhythm again.** The three spaces in it came from three
  unrelated expressions and worked out to 5, 3 and 11 points, so the speaker was glued to the icon
  beside it while the clock sat in a hole. All three now come out of a single number, derived so
  they cannot drift apart again. Windows XP and Windows 7 are untouched: XP carries the
  hidden-icons chevron and a differently proportioned speaker, and Windows 7 draws its own glyphs.

- **Pick the messenger in the tray: MSN or ICQ.** The icon file was called `icq.png` in every
  Windows theme while three of them held the MSN logo, which is why the code said ICQ and the
  taskbar said MSN. They are named for what they are now, and Windows 95, 98 and Me carry both, so
  Settings ▸ Dock offers the choice. MSN stays the default because that is what the tray has shown
  until now. Worth knowing while choosing: ICQ arrived in 1996 and MSN Messenger in 1999, so on a
  Windows 95 desktop the flower is the more period one of the two.

- **"Chaotic" crashes now actually happen.** The setting named for demos was the one that could
  not fire during a demo. Every tick asked whether the user was at the machine but between
  actions, which it read as idle time between three seconds and two minutes — and somebody who
  picks the demo setting then sits and watches stops touching the machine, sails past two minutes,
  and from that moment fails the test forever. Ten minutes of silence after launch sat on top of
  it. Chaotic now keeps only the lower bound, so a crash still never lands mid-keystroke, and its
  warm-up is thirty seconds; the other levels are unchanged, because for those the point is to
  catch you during a working day. The setting also says its cadence now, roughly every 25 minutes,
  instead of only "for demos" — twenty-five minutes of nothing was often correct and there was no
  way to tell. And the scheduler writes down what each tick decided, so "it is armed and nothing
  happens" is answerable: until now the two steps that swallowed the tick left no trace while the
  tab read "Armed".

- **The Mac menu bar matches the era again, without being asked.** macOS gives no way to recolour
  the menu bar, but it is translucent over the desktop picture, so RetroMac paints a strip of
  menu-bar height into the top of the wallpaper it renders anyway — System 6's white bar under its
  hard black rule, Platinum's flat grey, Aqua's pinstripes, the 10.6 gradient. That has been in the
  app for a while as a switch that was off unless you found it, which meant the first thing your eye
  landed on was the wrong menu bar. It is on by default now for the five Mac themes, still a switch
  under Desktop ▸ Wallpaper, and an explicit "off" is remembered. Windows themes are untouched: they
  either hide the bar or draw their own, and a grey band across the top of their wallpaper would be
  a defect rather than a tint.

- **The shareware episodes are in the Game Library.** Doom, Heretic, Duke Nukem 3D, Quake and
  Quake II each shipped a free episode that its publisher wrote a licence for: Duke's says in
  capitals that individuals are encouraged to give copies away. Those episodes now have a button
  on the card, beside what the game needs and what was found on your Mac. Four of the five were
  already in RetroMac — they are what happens today when you start one of those games with no data
  at all, which used to arrive as a surprise in the middle of launching. None of them overwrites a
  full game that is already there.

- **Quake II's demo download works again.** It pointed at an Internet Archive item that has since
  been taken down, so it had been failing silently. It now comes from id Software's own file
  archive: the original 1998 installer, unchanged, whose pak0.pak is byte-for-byte the one in the
  official demo. Doom's shareware episode is new; it is the one game here that never had a
  download at all.

- **The Game Library brings its own copy no more.** RetroMac downloads two games and only two:
  Freedoom, which is free software, and Shadow Warrior's shareware episode, which its publisher
  released for free distribution. The other eight are commercial games, and not one of the Archive
  items holding them states a licence, so RetroMac stops handing them out. Those cards still do
  the useful half of the job: they install the engine, name the exact file the engine wants, and
  look through your Steam libraries for the copy you already own — one press adopts it.
  Otherwise, point the card at your own files as before.

- **Cancelling a download now cancels it.** A cancelled multi-file title used to carry on
  downloading in the background with its card stuck on "downloading" forever, and a cancelled
  transfer could deliver its bytes into the NEXT title's folder under the next title's name — a
  half-finished Heretic replacing a working DOOM2.WAD. Both are fixed.

- **"Forget" no longer meant "delete".** Game data in a folder whose name merely began with
  "RetroMac", such as `RetroMac Backup`, was mistaken for RetroMac's own and would have been
  erased recursively by a sheet that promised only to forget the path.

- **Retro Crashes: fixes.** The sleep observer was removed from the wrong notification centre and
  piled up one per simulated crash. On a theme with no boot screen — Mountain Lion is one — the
  restored desktop after a simulated reboot flashed for two frames instead of holding its beat.
  And the list of apps that hold a crash back now looks at conferencing apps while they are merely
  running, not only while they are in front: OBS streams from the background, and sharing a screen
  in Zoom or Teams puts the shared window in front, never Zoom. Several explanations in the
  Crashes tab claimed more than the code checked and now say what they mean.

- **Credits say what is true.** Artwork borrowed for the themes was credited "for personal,
  non-commercial use", which is not what RetroMac is. Those passages now say what they actually
  are: unofficial fan tributes, with no ownership claimed and no affiliation with the rights
  holders.

- **Defrag has the drive to go with it.** The spindle spins up when you press Start and coasts
  down when the job stops, the head clatters across the platter on every cluster it moves, and a
  short tick lands as each one is written — all of it tied to what the window is showing rather
  than looped underneath it. A seek's texture follows how far the head just travelled, so a
  freshly fragmented disk stutters and a nearly sorted one only ticks, and the whole thing calms
  down as the progress bar fills. Pause leaves the platter turning and stops the seeking, because
  that is what a paused job sounded like. Nothing is sampled: it is three synthesised ingredients,
  so no recording of somebody else's drive ships under an unclear licence. There is a Sound button
  in the toolbar, and it remembers what you chose.

- **Retro Crashes.** Simulated system failures in period: the Windows 9x blue screen ("An error
  has occurred", the fatal exception, Windows protection error), the illegal-operation dialog, and
  the NT Stop screen with its memory dump for Windows XP and 7. A crash freezes the desktop —
  by laying a photograph of it over itself, so nothing is actually frozen — shows the error, and
  offers the recovery the machine of the day offered. Choose Ctrl+Alt+Delete and the screen goes
  black and the theme's boot screen plays.

  Nothing ever really crashes: no application is quit, no document closed, no restart issued, and
  no system setting is changed. That last part is the recovery story rather than a detail — since
  nothing global is touched, force-quitting RetroMac is itself a complete repair. Esc always ends
  it, switching to another app ends it, and it ends by itself after a minute.

  The Macintosh side is there too: the System 6 bomb with its always-dead Resume button, Mac OS 9's
  bus error with the advice to restart holding Shift, Mac OS X 10.0's text-console panic, and the
  grey "You need to restart your computer" curtain in its four languages for Snow Leopard and
  Mountain Lion.

  In Authentic mode a crash is a scene rather than a picture. For five or six seconds the pointer
  falls behind and then sticks, the picture starts tearing, and a hard disk spins up and begins to
  hunt — then the error arrives. Choose Restart and the screen goes black, the theme's boot screen
  plays, and the desktop comes back exactly as it was, because it was never touched.

  The drive is synthesised, not sampled: a spindle spinning up, the actuator seeking, and then the
  slow regular click of a head that has hit the stop and is retrying. Nobody's recording is
  shipped, and the sound can follow the length of the scene instead of being a fixed clip.

  The graphics glitches are the ones these machines really produced. Redraw trails — a window
  smeared across a desktop that has stopped repainting — only appear where they were possible:
  drawing straight into the frame buffer, so every Windows up to XP and both classic Mac systems,
  but not Windows 7 with its Desktop Window Manager and not Mac OS X, which composited from the
  start. Where the desktop ran in 256 colours the palette goes wrong; where it ran in millions, a
  colour channel arrives displaced instead.

  Each era has several failures rather than one, and picks between them: the 9x blue screens, the
  "System is busy" screen, and the invalid page fault blamed on whichever of EXPLORER, RUNDLL32,
  MSGSRV32 or IEXPLORE was unlucky; XP's "has encountered a problem" with Send Error Report, and
  Windows 7's "has stopped working"; the Macintosh bomb naming its fault the way each system
  version did, from "Bus Error" to "error type 11", and the plainer "application has unexpectedly
  quit" that did not take the machine with it; and on Mac OS X the panic plus the same news in
  Aqua. Every screen also fills its own blanks — addresses, stop codes and module names differ
  each time.

  The Windows dialogs are laid out the way the originals were, down to the buttons stacked in a
  column on the right and the register dump that unfolds behind "Details". Closing one does not
  always let you off: a program that had just performed an illegal operation often took the
  machine with it a moment later, so sometimes it does. There are two antivirus finds as well —
  Norton on the 9x machines, Symantec's notification window on XP — which are not crashes at all:
  nothing restarts, because nothing broke.

  No two crashes in a row look alike. The picker avoids the last scenario and the last shape of
  failure, so a blue screen is followed by a dialog or by the shell dying rather than by another
  blue screen — half the Windows 9x catalogue is a blue screen with different words on it, which
  is how a correct random pick can still feel like the same crash every time. The warning varies
  too: sometimes the pointer falls behind, sometimes the picture comes apart, sometimes both in
  turn, and sometimes the failure simply arrives.

  Dialogs keep the mouse pointer. Blue screens still take it away, because the machine was not
  answering, but a dialog you are meant to click needs something to aim with.

  One of them is not a screen at all: Explorer stops responding, the taskbar and the desktop icons
  disappear for a few seconds, and then the shell comes back. That was the most common Windows
  failure of the era by a distance, and it needs no overlay — RetroMac simply takes its own
  taskbar away and puts it back.

  A red "simulated crash" sits in the corner, and can be switched off for a video.

  Off by default. Set how often it may happen, from once a week to a demo mode, or leave it on
  manual. It stays quiet while the virtual camera is running, while something is being recorded,
  in front of Keynote, Zoom or Teams, and in the first ten minutes after launch. Part of the
  licence.

  The Windows 9x screen is drawn in the real 720x400 VGA text mode with the real VGA font
  (Px437 IBM VGA by VileR, CC BY-SA 4.0, credited in About), scaled up whole-number so the pixels
  stay square.

## 2.8.3

- **Putting your system cursors back is reliable now.** Restoring used to delete its own backup,
  so the next themed cursor re-captured whatever was on screen; after one imperfect restore the
  theme's cursors became the stored "originals" and the real ones were gone. The backup is kept
  for good now, capture refuses to run while a theme is applied, and restore tears the old state
  down before putting the originals back. It also restores per cursor identifier rather than per
  logical slot, which matters more than it sounds: five of the twelve slots have variants whose
  artwork genuinely differs, and the spinner alone is a 24x24 image of 24 frames under one name
  and a 28x40 image of 15 frames under another.
- **"Apply to Full Screen" is in the menu bar.** Only "Apply to Window..." had an entry, so once
  you had put the effect on a single window there was no visible way back. Both entries now sit
  together and the active one is ticked.
- Under the hood: the dock works out its row once instead of in four separate places that had to
  be kept in step by hand. That is what let the trash escape the bar in 2.8, and it had quietly
  caused two more mismatches nobody had noticed.

## 2.8.2

- **The trash sat outside the dock** on Snow Leopard and Mac OS X, and only snapped into place
  while the pointer was over the dock. The bar's width is worked out by listing every tile it will
  hold, and that list had no entry for the Dashboard icon, which was added to the dock later. The
  bar came out exactly one tile too narrow, so the last item — the trash — was drawn beside it;
  hovering hid the symptom because magnification reflows the row inside the bar. Mountain Lion was
  a tile short too, but has no trash, so nothing showed.

## 2.8.1

- **Exposé no longer hides RetroMac's own windows.** The window list skipped anything owned by
  RetroMac itself, which on a theme desktop is a large share of what you see: Television, the CPU
  monitor, Notepad, Calculator and App Folder windows are all ours. With only those open, Exposé
  reported "No windows" over a screen full of them. Nothing unwanted comes in as a result — the
  dock, Dashboard, the Exposé sheet, the pet, menus and desktop icons all sit above the window
  layer Exposé reads and were already excluded.
- With a second display attached, the screen that happened to hold no windows announced "No
  windows" while the other was showing them all. That message now means nothing anywhere.

## 2.8

- **Snow Leopard has its own chrome**: 10.6 no longer borrows Cheetah's early-Aqua look. Three
  themes used to share one chrome key, so a 2009 desktop wore a 2001 window. The title bar is
  measured off the original — unified grey, flat traffic lights, the separator along the bottom —
  and it comes with blue gel scrollers, period-correct icons for Chrome, iWork, Claude and
  ChatGPT, and the striped Macintosh HD.
- **Dashboard is back**: the widget layer macOS dropped in Catalina, rebuilt. Ctrl+F12 brings up
  Clock, Calculator, Weather (Open-Meteo, no key, no account), Calendar, Stickies, a Google search
  pill and a CPU monitor. Add and remove them from the bar, drag them where you like, and they
  stay put.
- **Exposé**: every window on the desktop, shrunk so none overlap, each card travelling from where
  its window actually sits. Ctrl+F9 for all of them, Ctrl+F10 for the front app — or hold a dock
  icon, the way 10.6 changed that gesture to work.
- **Stacks, drawn the way 10.6 drew them**: Applications and Downloads open as a grid with real
  Quick Look previews, sitting next to the Trash where they belong, and hanging from the callout
  nose that points back at the dock icon.
- **Disk Defragmenter**: the Windows 95 and 98 themes get the defrag widget, with its authentic
  icon, a working scrollbar and a period-correct pace.
- **Desktop extras**: the real Flurry screensaver for the Mac OS X themes, five more Snow Leopard
  wallpapers (Rocks, Earth, Aurora Blue, Zebra, Stones), and an optional tint for the menu bar so
  a modern translucent one stops fighting the theme.
- **Phosphor persistence**: afterglow across frames, applied to the signal ahead of the mask, in
  every Metal renderer.
- **Settings have a Shader tab**: what was "Advanced" is now Shader, and it leads the sidebar.
  The effect's settings used to be spread over three tabs and five sections; they are in one place
  now — Preset, Look, Where, Per-App, Performance and When. Hotkeys and system setup moved to tabs
  of their own.
- **Fixes**: the shader's per-theme on/off is no longer overruled at launch, and switching it off
  no longer discards which preset the theme was assigned; the Quality picker stops resetting a
  frame rate you chose, and 120 fps is offered only on panels that reach it; a failed theme import
  can no longer lose the theme it was replacing; Hover! is genuinely offline (its last two remote
  references are gone); the shader and the dock pin their display by UUID rather than by display
  id, so they stay put across a reconnect; widgets stop rendering a cached copy of themselves
  after an update; every readme window can be dragged; file paths coming from the App Folder web
  view are validated; every boot screen shows for the same five seconds; and beta disk images are
  named after their version, so a beta can never again be shipped as the release.

## 2.7

- **Windows 95 theme**: the one that started it all. Solid navy title bars, the silver
  `#C0C0C0` chrome, the clouds wallpaper, an authentic boot screen, and Win95 shell icons
  throughout. The Start menu is period-correct: large icons in a narrow first level, small
  ones in the wider submenus, and no Windows Update or Log Off (Windows 95 had neither).
- **Fun Stuff (D:)**: the CD-ROM is back on the desktop. Open it and browse `FUNSTUFF` into
  `HOVER`, `VIDEOS` and `PICTURES` — music videos play in a bare title-bar window, and
  `Clouds.exe` / `WINBMP.EXE` set your wallpaper the way a 1995 CD-ROM would.
- **Hover! plays again**: the Microsoft HTML5 remake, self-hosted and fully offline in its
  classic pixel-graphics mode. No Wine, no emulator, no internet.
- **Authentic Win95/98 details**: scrollbars with a single arrow at each end, raised bevels
  and a dithered track; the status bar below its own scrollbar row; the program icon back in
  the title bar; and no running-app dots under quick-launch icons on 98/Me/XP, where the
  taskbar already shows running programs.
- **Readmes overhauled**: every theme's "About This Theme" is closable again, fills its
  window edge-to-edge, sizes itself so it needs no scrolling, and shows its hero artwork.
  Futurama finally has one too.
- **Start into your theme**: a new opt-in setting activates your last theme right at launch
  instead of the clean desktop.
- **Fixes**: Windows 95 title bars no longer showed the Windows 98 gradient (which also
  repaired every Windows 98 Plus! colour scheme), file lists are white instead of grey,
  desktop icon labels stop colliding, boot videos are no longer cropped at the bottom,
  `sheep.exe` works on Windows 95, and the Classic Teal wallpaper is the canonical `#008080`.

## 2.6

- **Windows Me theme**: Millennium Edition joins the family — the Me Start-menu banner in its
  brush-script logo, a 4K-remastered wallpaper, an authentic boot splash, and Me shell icons
  (oval Recycle Bin, Media Player). "Windows Update" sits atop the Start menu, and it gets the
  full special-theme treatment (systray, taskbar auto-hide, desktop pet).
- **Windows 7 Aero, refined**: the Start menu now has its glass frame and the account picture that
  peeks above the top edge; the taskbar is real translucent Aero glass; and the notification area
  is authentic — a flat tray with an up-chevron, network + volume icons that open the matching
  macOS settings, and a two-line time/date clock.
- **100% themes**: the marker on the fully-realised themes is now a 100% badge shown after the
  theme name (Futurama counts too).
- **Flyout upgrades**: drag Quick Access tiles to reorder them in Edit mode, double-click the
  floating button to toggle your last theme, and the menu-bar Apple-logo cycle now includes the
  Futurama teal apple.
- **New shaders**: NLO VHS SP — a real single-pass NTSC comb-demodulation with authentic dot crawl
  and cross-colour — and CRT EasyMode, a clean, sharp mask-and-scanline CRT.
- **Windows 98 / Me icon fixes**: Safari maps to the IE icon, and running Chrome/Firefox show their
  real icons again instead of IE.
- **Fix**: a pasted licence key is no longer white-on-white in the Activate field.

## 2.5

- **Futurama theme**: a Planet Express take on the desktop. The dock is the show's riveted metal
  girder: a pressure-gauge control panel on the left, a recessed glass shelf your icons rest on,
  and a grille end cap on the right. It comes with a teal Bender-and-friends icon set, the Planet
  Express wallpaper, a teal Apple logo, and bold cel-shaded window outlines.
- **Restore system cursor**: a new button in Cursor settings puts the normal macOS pointer straight
  back if a themed cursor ever gets stuck. RetroMac also recovers the cursor reliably on the next
  launch now, even if it was force-quit while a themed cursor was active.
- **Fix (all custom docks)**: minimizing or restoring a window, or changing your pinned apps, now
  resizes the dock immediately instead of leaving it the wrong size until you moused over it.

## 2.4

- **NeXTSTEP theme**: the full NeXT desktop, rebuilt natively. A vertical Workspace menu top-left,
  a right-edge dock of grey tiles with a live clock/calendar and the Recycler, black title bars with
  the miniaturize box left and close box right, the four-grey chiseled bevel throughout, and the
  MegaPixel grey-violet wallpaper. Running apps float free on the workspace as draggable icons that
  snap to a grid, and the NeXT cursor replaces the pointer.
- **File Viewer**: the NeXT Workspace file browser, with the shelf of category drawers, a
  current-location path strip, the icon grid of your installed apps and TV streams, and the
  authentic left-side scroller (arrows grouped at the bottom, dimpled knob). It opens on its own
  when the theme starts, as it always did on NeXTSTEP.
- **Change any dock or app icon**: right-click a tile and pick from 120 authentic NeXT "Fleet"
  icons or your own image. A "fill the whole tile" option decides whether the pick covers the
  cell edge-to-edge or sits inset on the silver tile.
- **TV in themed windows**: the Classic Themed Window for TV streams now wears the NeXT window
  chrome too (it already matched BeOS, Mac OS 9, Windows XP and System 6).
- **Stable theme identity (under the hood)**: themes now carry a stable id, so renaming or
  duplicating a theme keeps its wallpaper, dock position, preset and other per-theme settings, and
  two themes can share a name without clashing. Existing settings migrate automatically on first run.
- **Fixes**: bringing a running app back to the front from its NeXT icon now works reliably; the
  System Tweaks boolean restore and the wallpaper restore both round-trip correctly.

## 2.3

- **Windows 7 Aero theme**: the Superbar taskbar with the Start orb, translucent glass window
  titles, and the Aero wallpaper.
- **Windows 98 Plus! themes**: pick a scheme under Settings ▸ Dock ▸ Scheme (Dangerous Creatures,
  Leonardo da Vinci, More Windows). Each recolours the whole Windows 98 look (title bars, windows,
  start menu) and swaps the wallpaper, desktop icons and mouse cursors.
- **Mac OS System 9**: pixel-accurate Platinum title bars, proxy icons, a Finder info bar,
  WindowShade collapse, authentic desktop/proxy icons, an expanded icon set, imported classic
  wallpapers, colour Nyanochrome and Tic-Tac-Toe widgets, and a cleaner inactive-window state.
- **Dockable Control Strip**: the System 9 Control Strip now snaps flush to the left or right
  screen edge (Settings ▸ Dock), mirrors correctly, and gains scroll chevrons when it overflows,
  just like the historical original.
- **Window borders**: per-window themed borders are steadier when windows change focus or space,
  and clear more promptly on minimize.
- **Calculator widget** for the Windows 98 and XP themes, plus an authentic Windows 98 screensaver
  icon and a working Edit/View/Help menu bar on the Windows calculator.
- **Warcraft I + II**: a theme-matched title bar drawn by the engine, so the game sits in a normal
  window on the themed desktop with the dock beside it (hidden only in fullscreen).
- **Setup Assistant**: a Games step to point RetroMac at your Doom, Quake, Duke Nukem and Warcraft
  files (and add desktop shortcuts), and a final step to pick the theme to start with. The
  "shader on theme change" default is now off.
- **Security**: imported themes can no longer run system tweaks or reach files outside their
  bundle; system tweaks are only dropped from the restore snapshot once they are actually reverted,
  so a transient failure can no longer strand a changed setting; a refunded or revoked licence is
  now detected on revalidation.
- **Fixes**: the real macOS Dock is restored when RetroMac's dock is turned off; Mac OS X Cheetah
  title-bar hover no longer flickers; assorted polish.

## 2.2

- **One-time manual update**: 2.2 changes how updates are delivered (a new signing key), so
  existing copies cannot install it automatically. Download 2.2 once and drag it into
  Applications; automatic updates resume from 2.3 on.
- **Authentic Mac System 6**: a true 1-bit black and white theme.
- **Warcraft I + II**: play them natively on the bundled Stratagus engine with your own game data.
- **Mac OS X boot animation** for the Mac OS X and Snow Leopard themes.
- Clearer Pro unlocks and assorted polish.

## 2.0

- **Themed mouse cursors**: each theme can replace the whole system cursor (classic Mac pointer
  with ticking wristwatch / rotating spinner, Mac OS X Aqua with the spinning beach ball,
  Windows XP, retro Windows 3.1). Toggle under Settings ▸ Dock ▸ "Match cursor"; your own cursor
  is captured and restored exactly when the theme goes off.
- **Windows XP cursor sizes**: Normal, Large or XL while the XP theme is active.
- **BeOS unified**: "BeOS" and "BeOS Classic" are one theme now, with a switch between the corner
  Deskbar and a regular dock.
- **Per-theme icon sizes**: dock and desktop icon-size sliders are remembered per theme.
- **Setup Assistant**: opt in (on by default) to matching the macOS colour scheme and the cursor.
- Fixes: menu-bar Apple logo resets when a theme or the app turns off, opaque System 6 Control
  Strip with a new boot splash, plus TV-Tube and Duke Nukem / GZDoom launch fixes.

For the 1.9.2 through 1.9.7 and 2.1 releases, see the
[GitHub Releases](https://github.com/klotzbrocken/RetroMac/releases).

## 1.9.1.1

- **iPhone as a camera source** — pick your iPhone (Continuity Camera) or any webcam in
  Settings ▸ Camera & Streaming; the list updates live as devices connect, and the CRT
  shader runs on the feed.
- **"Dock only" really means dock only** — switching a theme with Dock only on no longer
  touches the wallpaper, desktop icons, widgets or boot splash, and won't start a
  full-screen shader.
- **Multi-monitor Lite shaders** — the lightweight (Lite) presets now appear on the
  selected display, not just the main one.
- **TV windows** no longer borrow the last used theme's menu bar / chrome when no theme
  is active.
- **Tidier quick-access flyout** — the shader toggle and preset dropdown stay correct
  after switching presets; active theme highlighted correctly; Settings/Quit are icons;
  floating launcher on by default.
- **Dock fixes** — clicking a Dock tile reliably brings a running app's window to the
  front; correct flyout & Dock-Mode icons across themes; desktop-icon visibility respects
  other apps.

> Supersedes 1.9.1, which was retracted before wide distribution.

## 1.9.0

- **Dock Mode & quick launcher** — optionally show RetroMac in the Dock; click its icon
  for a slim launcher to switch themes and toggle the shader or virtual camera.
- **Authentic Windows taskbar** — Windows 98 and XP show one elongated taskbar button per
  open window; click to minimize or restore.
- **Shaders on all displays** — the CRT shader now works on secondary monitors.
- **New "Retro Crisis" GDV-NTSC shaders** (Composite & RGB) and softer, more authentic
  phosphor masks.
- Setup Assistant, redesigned Settings, custom Metal shader import, and reliability fixes.

## 1.8.x and earlier

See the [GitHub Releases](https://github.com/klotzbrocken/RetroMac/releases) page for
release notes and downloads.
