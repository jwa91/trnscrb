# trnscrb — Feature Roadmap

> Planning doc — tracked in git, not shipped.

## North Star

Drop anything from anywhere (Mac, iPhone, browser, Raycast) into a single ecosystem that produces structured markdown in a configured folder. This markdown feeds into a downstream AI "compiler" pipeline that transforms raw captures into typed, structured content (YAML + markdown) for the knowledge system.

trnscrb is the **Mac desktop capture layer** in this pipeline.

---

## Cmd+V Paste Support

**Goal:** Pasting copied files from Finder or `pbcopy` content into the popover triggers the same processing pipeline as drag-and-drop.

**Status:** Implemented

---

## Global Hotkey

**Goal:** A user-configurable keyboard shortcut that activates trnscrb from anywhere.

**Status:** To Do

---

## Standard Mac Keyboard Shortcuts

**Goal:** Cmd+, opens settings. Other standard shortcuts work as expected.

**Status:** Implemented

---

## Raycast Extension

**Goal:** A Raycast extension that sends files or clipboard content to trnscrb for processing.

**Status:** To Do

---

## Browser Extension

**Goal:** Right-click an image or PDF in a browser, send it to trnscrb.

**Status:** To Do

---

## Synergy with Capture (iPhone app)

**Goal:** Unify the capture-to-markdown pipeline across Mac and iPhone so both feed into the same vault/folder structure.

**Status:** To Do

---

## Stay open checkbox

**Goal:** a checkbox that allows users to leave the menubar app open, even if they click outside the window, usefull for creating lots of files.

**Status:** To Do

---

## No S3 cloud connection

**Goal:** directly upload files to Mistral, instead of via S3, make S3 optional, Add S3 upload as a more standalone feature as well

**Status:** To Do

---

## Hotkey settings

**Goal:** make hotkeys configurable

**Status:** To Do

---

## Bundle ID migration

**Goal:** rename the app identity from `com.trnscrb.app` to `com.janwillemaltink.trnscrb`, reset the keychain namespace cleanly, and verify signing/notarization behavior after the change.

**Status:** In Progress
