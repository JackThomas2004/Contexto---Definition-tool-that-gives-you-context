# Contexto — AI Word Definer for macOS

> This small project aims to make it more convenient for people reading documents to quickly get definitions of terminology that is unclear by defining the word or phrase within the given context of the webpage, pdf doc, word file etc... , it does this by querying a term to a openAI model and then the LLM returns the definition within the articles context by quickly scanning over the article. This hopefully saves readers time by not having to switch tabs to find out what a word means which inherently also assist's with preventing a reader from loosing their flow whilst reading! Enjoy & I hope it provides some use to scholars and anyone else who would like to give it a try!

> Highlight a confusing word or phrase while reading online. Right-click → Services → **Define with Contexto**. Get an AI-powered definition that understands the article you're reading.

---

## What it does

Contexto is a lightweight macOS menu-bar app (the ◉ icon in your top-right menu bar) that uses OpenAI's GPT-4o mini to explain words and phrases in context. Unlike a dictionary, Contexto first reads the article you're viewing and crafts a definition specific to that topic.

---

## Requirements

| Requirement | Details |
|---|---|
| macOS | 12 Monterey or later |
| Xcode Command Line Tools | Run `xcode-select --install` if not already installed |
| OpenAI API key | Get one free at [platform.openai.com/api-keys](https://platform.openai.com/api-keys) |

---

## Installation (3 steps)

### Step 1 — Build

Open Terminal, navigate to this folder, then run:

```bash
chmod +x build.sh install.sh
./build.sh
```

This compiles the Swift source files and produces `build/Contexto.app`.

### Step 2 — Install & Launch

```bash
./install.sh
```

This copies the app to `~/Applications/`, flushes the macOS Services database, and launches Contexto. You should see the **◉** icon appear in your menu bar within a few seconds.

### Step 3 — Add Your API Key

1. Click the **◉** icon in the menu bar
2. Choose **Preferences…**
3. Paste your OpenAI API key (`sk-proj-...`) and click **Save**

You can get a key at [platform.openai.com/api-keys](https://platform.openai.com/api-keys).

---

## First-time macOS permissions

The first time Contexto tries to read your browser tab, macOS will ask for permission:

- **Automation access** — allows Contexto to read the URL and page text from Safari / Chrome / Brave / Arc via AppleScript. Click **OK**.

If you missed the prompt, go to:  
**System Settings → Privacy & Security → Automation**  
and enable Contexto for your browser.

---

## Enable the Services menu item

If "Define with Contexto" doesn't appear when you right-click selected text:

1. **System Settings → Keyboard → Keyboard Shortcuts → Services**
2. Under **Text**, find **Define with Contexto** and tick the checkbox ✓

You may also need to log out and log back in once after the first install for the service to register.

---

## Usage

1. Open any article in Safari, Chrome, Brave, Arc, or Edge
2. Select a word or phrase you don't understand
3. Right-click → **Services → Define with Contexto**
4. A floating panel appears with the definition

Alternatively:
- Copy any text, then click **◉ → Define from Clipboard**

---

## Launch at Login (optional)

To have Contexto start automatically when you log in:

**System Settings → General → Login Items**  
Click **+** and add `~/Applications/Contexto.app`

---

## How it works (architecture)

```
User selects text
        │
        ▼
macOS Services mechanism
        │
        ▼
AppDelegate.handleDefineWithContexto(_:)
        │
        ├──► BrowserService.getCurrentPageInfo()
        │         │  AppleScript → active browser tab
        │         └─ URL + title + first 2,000 chars of body text
        │
        ├──► AIService.define(term:pageInfo:apiKey:)
        │         │  POST https://api.openai.com/v1/chat/completions
        │         │  Model: gpt-4o-mini
        │         └─ Returns 2-4 sentence context-aware definition
        │
        └──► DefinitionWindowController.showDefinition()
                  Floating panel, above other windows, near cursor
```

**Supported browsers:** Safari, Google Chrome, Brave, Arc, Microsoft Edge, Firefox (title only)

---

## Files

```
Contexto/
├── Sources/
│   ├── main.swift               Entry point
│   ├── AppDelegate.swift        Menu bar icon, Services handler
│   ├── AIService.swift          OpenAI API calls
│   ├── BrowserService.swift     AppleScript browser reader
│   ├── DefinitionWindow.swift   Floating result panel
│   └── PreferencesWindow.swift  API key settings
├── Resources/
│   └── Info.plist               App metadata + Services registration
├── build.sh                     Build script
├── install.sh                   Install & register script
├── create_icon.py               Icon generator (pure Python)
└── README.md                    This file
```

---

## Troubleshooting

**The ◉ icon doesn't appear after install**  
Run `./install.sh` again. If it still doesn't appear, try opening the app directly: `open ~/Applications/Contexto.app`

**"Define with Contexto" doesn't show in the right-click menu**  
Go to System Settings → Keyboard → Keyboard Shortcuts → Services and enable it. Log out and back in if needed.

**I get "Automation" permission errors**  
Go to System Settings → Privacy & Security → Automation and enable Contexto for your browser.

**Gatekeeper blocks the app on first open**  
Because the app isn't notarized with a paid Apple Developer account, macOS may warn you. Right-click `Contexto.app` and choose **Open**, then confirm. You only need to do this once.

**The definition doesn't mention the article topic**  
Make sure Contexto has Automation permission for your browser (see above). Without it, only the selected text is sent to OpenAI — definitions still work but without article context.

---

## Privacy

- Your selected text and article content are sent to OpenAI's API to generate definitions.
- Your API key is stored in macOS user preferences (`~/Library/Preferences/com.contexto.app.plist`).
- No data is stored by Contexto itself.
- Review OpenAI's privacy policy at [openai.com/policies/privacy-policy](https://openai.com/policies/privacy-policy).

---

*Contexto v1.0 — Built with Swift + OpenAI API*
