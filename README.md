# X Free

A personal macOS client for 𝕏, built as a multi-column TweetDeck-style layout with ad-blocking.

## Configuration

`⌘,` opens the settings folder. Edit `settings.json` and restart the app.

```json
{
  "$schema": "./schema.json",
  "columnWidth": 450,
  "columns": [
    {
      "type": "custom",
      "url": "https://x.com/i/bookmarks"
    },
    {
      "type": "custom",
      "url": "https://x.com/home"
    },
    {
      "type": "custom",
      "url": "https://x.com/i/grok"
    }
  ]
}
```

Supported column types: `forYou`, `following`, `notifications`, `profile`, `custom` (with `url`).

## Shortcuts

- `⌘+` / `⌘-` — zoom
- `⌘R` — refresh
- `⌘,` — open settings folder

## Credits

X Free is a personal fork of [XDeck](https://github.com/morishin/XDeck) v2.3 by [@morishin](https://github.com/morishin), released under the MIT License. The foundation — column layout, WebView plumbing, ad-blocking — belongs to the original author.
