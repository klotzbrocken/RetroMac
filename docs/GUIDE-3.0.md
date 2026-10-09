# Using RetroMac 3.0

What is new in 3.0 and how to use it. Settings are in [SETTINGS.md](SETTINGS.md), the full list
of changes in the [Changelog](../CHANGELOG.md).

## Rescue Desktop

When the desktop is stuck (a window rolled up that will not come back, a window somewhere off
screen, a theme that misbehaves), rescue it:

- press **⌃⌥⌘R**, or
- choose **Rescue Desktop** in the flyout or in the menu-bar menu.

RetroMac turns the theme, the shader and every desktop effect off, unrolls rolled-up windows,
brings windows whose title bar you cannot reach back onto a screen, and restores the Dock, the
menu bar, the wallpaper and the cursor. Your settings stay as they were. A report says what was
done, what was skipped and what did not work.

It works with no theme on, too. If RetroMac quits in the middle, the next start turns nothing on
and finishes the rescue. `open -a RetroMac --args --rescue-desktop` starts a rescue from the
command line. Change the shortcut in Settings ▸ Shortcuts.

Bringing windows back needs the Accessibility permission. Without it the rest is still done and
the report says the windows were not checked.

## A theme on some Spaces only

To keep the theme to one Space (or a few) and plain macOS on the others:

1. Switch to the Space that should have the theme.
2. Choose **Themes ▸ On This Space** in the menu-bar menu.

The theme's dock, desktop and panels now live on that Space and slide away with it. On the
other Spaces you have the Mac's Dock, menu bar, cursor and your own wallpaper, and the shader
pauses. Add more Spaces the same way, or in Settings ▸ General ▸ Spaces. **Themes ▸ On All
Spaces** puts the theme back everywhere.

The appearance, accent colour, Finder and Terminal changes and hidden desktop icons stay on
every Space: macOS keeps them for the whole Mac.

## The window switcher

**⌃⌥Tab** switches windows the way the theme's era did; **⌃⌥⇧Tab** goes the other way.
Command-Tab stays the Mac's.

| Theme | What ⌃⌥Tab does |
|---|---|
| Solaris 8 — CDE | Each press gives the focus to the next window at once, as CDE's Alt+Tab did. No panel. Hold ⌃⌥ while you press Tab again and again; the order is fixed while you hold. |
| Snow Leopard | Opens Exposé with every window |
| Mountain Lion | Opens Mission Control |
| Mac OS X 10.0, System 6/7, Mac OS 9, Windows 3.1, BeOS, NeXTSTEP, OS/2, IRIX, Amiga | Nothing: their era had no such switcher. |
| Windows 95 … 7, QNX | Nothing yet: their switchers come once they are checked against the originals. |

Settings ▸ Shortcuts ▸ Window switcher says what it does in the theme you have on, changes the
keys, and turns it off for a theme. While it is off, or the theme has none, the keys are left to
other apps.

## Historic icons for modern apps

A theme can wear icons for today's apps, drawn in its era's style (Claude in Solaris colours,
say). They come as an icon package: a folder with the PNGs and an `icons.json`.

1. Choose the theme.
2. Open Settings ▸ Dock ▸ Historic icons and click **Import…**.
3. Pick the package folder.

RetroMac checks every file first. A broken one is named with its reason, and an app keeps its
working icon. The card shows how many icons are in, how many apps here use them, how many
common apps still have none, and how many were turned away. **Remove** takes the package out
again.

The icons appear wherever the theme shows the app: the dock, taskbars, the shelf and Front
Panel, menus, title bars and Exposé. An app with no icon in the package keeps its own. Your own
icon for an app (from the dock's context menu) still comes first.

The package format: [ICON-PACKAGES.md](ICON-PACKAGES.md) (German).

## Solaris 8 — CDE

The **Front Panel** at the bottom is the dock:

- A click on a control opens what it stands for. The clock opens Clock, the calendar Calendar, the
  drawer your home folder, the pen TextEdit, the letter your mail app.
- The little **arrow** above a control opens its subpanel. A click outside or Esc closes it.
  Drop an app on **Install Icon** to keep it there; right-click it to take it out again.
- The four workspaces **One … Four** open Mission Control. The lock starts the screen saver.
  **EXIT** turns the theme off.

On the desktop:

- **Right-click** the desktop for the **Workspace Menu**: your applications, folders, help,
  RetroMac's settings, Lock Display and Exit Theme.
- The **box at the left of a title bar** opens the window menu (Restore, Minimize, Maximize,
  Close). A double-click on it closes the window.
- A **minimised window** lies on the desktop as an icon, top left. Click it for its window menu,
  double-click it to bring the window back.
- **Applications ▸ Application Manager** shows your apps in Solaris-style groups, and all of
  them in All_Applications.

## QNX 6.2.1 — Photon

The **shelf** on the right edge:

- A click on a group's title (**Applications**, **Configure** …) folds it open or shut. RetroMac
  remembers which are open.
- The launchers open Mac apps and settings: Voyager is your web browser, Editor is TextEdit,
  and Configure leads to System Settings.
- **System Monitor** shows your Mac's CPU and memory load live.
- **World View** opens Mission Control.
- When the open groups do not fit on the screen, scroll the shelf.

The **taskbar** at the bottom:

- **Launch** opens the Launch menu: your apps by category (MultiMedia, Editors, Utilities,
  Internet, Development), Configure, Help, and **End Photon session**, which turns the theme
  off. **Add Application…** at the end of a category puts any app there; **Software ▸ Reset
  Categories** sorts them as they came.
- There is one entry per window. A click brings that window to the front.
- The clock opens Date & Time.

A **right-click on the desktop** opens the same Launch menu where you clicked.
