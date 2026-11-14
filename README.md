# Easy Peasy

Easy Peasy is a small floating desktop widget for macOS. Open a webpage, pick Translate or Simplify, and click **Peasify**: the text on the page is rewritten in place, in your browser. The button then turns red and reads **Unpeasify**; click it to put the original page back.

- **Translate** into a language you pick.
- **Simplify** hard English into easier English: Foreigner (1st grade level), Beginner (4th grade) or Intermediate (7th grade).

## Requirements

- Apple Silicon Mac, macOS 14 or later
- Swift toolchain (the Xcode Command Line Tools are enough)
- Safari, Chrome, Arc, Edge or Brave
- An [OpenRouter](https://openrouter.ai/keys) API key

## Set up

1. Copy `.env.example` to `.env` and paste your OpenRouter key after `OPENROUTER_API_KEY=`. `.env` is git-ignored; never put a key in `.env.example`.
2. Optionally set `OPENROUTER_MODEL` to any model from openrouter.ai/models.
3. In your browser, turn on **Allow JavaScript from Apple Events** (Safari: Develop > Developer Settings; Chrome and others: View > Developer).

## Build and run

```sh
scripts/bundle.sh
open build/EasyPeasy.app
```

The widget appears at the bottom centre of the screen and can be dragged anywhere. There is no Dock icon; quit from the leaf icon in the menu bar. The first time you click Peasify, macOS asks whether Easy Peasy may control your browser; allow it.

## Privacy

Page text is read only when you click Peasify and is sent to OpenRouter and the model provider behind it. Nothing is saved to disk.
