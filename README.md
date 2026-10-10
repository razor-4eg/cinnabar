<p align="center">
  <img src="docs/icon.png" width="128" alt="Cinnabar">
</p>

<h1 align="center">Cinnabar</h1>

<p align="center">
  A native macOS app for saving videos from online platforms.<br>
  Paste a link, pick a quality, and the file lands in a folder on your Mac.
</p>

<p align="center">YouTube, TikTok, Instagram, Vimeo, X, Twitch, Facebook, Reddit, VK, Rutube, and the other sites yt-dlp supports.</p>

<p align="center">Follows the system language: English, German, Spanish, French, Japanese, Portuguese, and Russian.</p>

<p align="center">
  <img src="docs/screenshots/download.png" width="780" alt="A video ready to download, with the qualities that video actually offers">
</p>

## Features

- Accepts a link to a single video from the online platforms [yt-dlp](https://github.com/yt-dlp/yt-dlp) supports. Popular ones include YouTube (watch links, `youtu.be`, Shorts, live streams, and embeds), TikTok, Instagram, Vimeo, X, Twitch, Facebook, Reddit, VK, and Rutube. A playlist or channel page is not downloaded as a whole.
- Quality choices follow that video: Best, the resolutions it actually offers, and audio only. On YouTube that can be 4K, 1440p, 1080p, 720p, or 480p. Each quality is saved as its own file, so a later download in another quality does not replace the one you already have.
- A queue runs two downloads at a time. The rest wait their turn.
- A library of finished videos, with thumbnails, file size, and the quality on disk. Open a file, reveal it in Finder, or move it to the Trash.
- Files go to `~/Downloads/Cinnabar` unless you pick another folder from the toolbar or from Settings.
- Drag a link onto the window, or press **⌘R** to look it up and **⌘↩** to start the download.
- Closing the window leaves Cinnabar in the Dock. Clicking the icon opens the window again.

<p align="center">
  <img src="docs/screenshots/library.png" width="780" alt="Library of saved videos">
</p>

## Requirements

- macOS 14 or later
- Swift 6, from Xcode or the Command Line Tools
- A network connection the first time Cinnabar fetches its download tools

## Install

Download `Cinnabar-1.0-macOS.zip` from the [releases](https://github.com/razor-4eg/cinnabar/releases), unzip it, and move `Cinnabar.app` to Applications.

The release is ad-hoc signed and not notarized, so macOS blocks the first open. Try to launch it once. Then open **System Settings → Privacy & Security**, scroll to Security, and click **Open Anyway**. Confirm with your password. After that, Cinnabar opens with a double-click. The button stays available for about an hour after the blocked launch.

Or clear the download quarantine from Terminal. Use the path where the app actually is:

```bash
xattr -dr com.apple.quarantine /Applications/Cinnabar.app
```

A copy you build yourself does not need either step.

## Build

From the project directory:

```bash
./scripts/build.sh
open build/Cinnabar.app
```

The script draws the icon, compiles a release build, and assembles an ad-hoc signed `build/Cinnabar.app`. If yt-dlp is already installed for your user, the script copies it into the app.

Run the tests with:

```bash
swift test
```

## Components

Cinnabar does not download videos itself. It uses three free tools:

| Tool | Role |
| --- | --- |
| **yt-dlp** | Reads the page and downloads the streams. |
| **ffmpeg** | Merges separate video and audio into one MP4. That includes 1080p and 4K when the site splits them. Without ffmpeg, Cinnabar saves one ready-made file. |
| **ffprobe** | Looks at the finished file so yt-dlp can confirm the streams. Downloads still work if it is missing. |

On first launch, **Install** downloads anything that is missing:

- yt-dlp comes from the [yt-dlp GitHub releases](https://github.com/yt-dlp/yt-dlp/releases).
- ffmpeg and ffprobe come from [evermeet.cx](https://evermeet.cx/ffmpeg/). If Homebrew already provides ffmpeg, Cinnabar uses that copy and does not download another one.

Cinnabar keeps its own copies in `~/Library/Application Support/Cinnabar/bin`. Settings can install what is missing, replace Cinnabar's copies with fresh ones, or remove them. ffmpeg installed with Homebrew is left alone.

Sites change often enough that an old yt-dlp eventually stops working. Update it from Settings when a video that used to download starts failing. ffmpeg rarely needs an update.

Some pages still will not download. yt-dlp marks a few sites as broken, and that list moves. A site that asks you to sign in needs browser cookies, which Cinnabar does not send. Protected streams, such as subscription movie services, are out of reach. A playlist or channel link is limited to one item, not the whole collection.

<p align="center">
  <img src="docs/screenshots/settings.png" width="560" alt="Settings, with the download folder and component actions">
</p>

## Firewall prompts

yt-dlp connects to the network on its own. A firewall such as LuLu asks for permission per program, so allowing Cinnabar is not the same as allowing yt-dlp. When the prompt appears, allow it. If nothing happens and no prompt shows up, add an allow rule for the yt-dlp helper yourself.

## Project layout

```
Sources/Cinnabar/          SwiftUI interface
Sources/CinnabarCore/      Link parsing, yt-dlp, and ffmpeg
Resources/              App metadata, icon, and localizations
scripts/build.sh        Release build
Tests/CinnabarCoreTests/   Engine tests
```

Only save videos you are allowed to download.
