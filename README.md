<h1 align="center">X Free</h1>
<p align="center">Your favorite 𝕏 client for macOS, now in compact mode</p>

<p align="center"><img src="assets/preview.png" alt="X Free" width="800"></p>

---

<p align="center">
    <img src="https://img.shields.io/badge/Built_with-Swift-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Built with Swift">&nbsp;
    <img src="https://img.shields.io/badge/Platform-macOS-0071E3?style=for-the-badge&logo=apple&logoColor=white" alt="macOS">&nbsp;
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-2E8B57?style=for-the-badge" alt="MIT License"></a>
</p>

## Install

Download the latest `.dmg` from the [Releases](https://github.com/dbkarashev/xfree/releases) page and drag **X Free** into your Applications folder.

X Free isn't notarized, so on first launch macOS will say it's from an "unidentified developer". Right-click the app → **Open** → **Open** in the dialog. macOS remembers your choice; subsequent launches behave normally.

### Building from source

```sh
git clone https://github.com/dbkarashev/xfree.git
cd xfree
open XFree.xcodeproj
```

In Xcode → **Signing & Capabilities**, switch the team to your own (the project ships with the maintainer's), then **Product → Run** (`⌘R`).

## Settings

<kbd>⌘</kbd> <kbd>,</kbd> opens Settings.

- **General** — appearance (light or dark, default light), hide ads on x.com.
- **Columns** — compact mode toggle, auto vs manual width, drag to reorder, swipe to delete.

Column types: `For you`, `Following`, `Notifications`, `Profile`, `Custom URL`. Custom URLs on `x.com` / `twitter.com` get the same ad-block treatment as built-in columns.

## Shortcuts

| | |
| --- | --- |
| <kbd>⌥</kbd> <kbd>/</kbd> | Toggle compact mode |
| <kbd>⌘</kbd> <kbd>R</kbd> | Refresh |
| <kbd>⌘</kbd> <kbd>+</kbd> · <kbd>⌘</kbd> <kbd>-</kbd> | Zoom in / out |
| <kbd>⌘</kbd> <kbd>1</kbd> … <kbd>⌘</kbd> <kbd>9</kbd> | Jump to column N (compact mode) |
| <kbd>⌘</kbd> <kbd>,</kbd> | Settings |

## Credits

Fork of [XDeck](https://github.com/morishin/XDeck) v2.3 by [@morishin](https://github.com/morishin). Original column layout, WebView plumbing, and ad-blocking are theirs.

This project is licensed under the [MIT License](LICENSE).
