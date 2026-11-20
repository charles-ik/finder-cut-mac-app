# Finder Cut

A tiny menu bar app that adds cut and paste for files in Finder: ⌘X, then ⌘V moves them.

It edits the real keypress as it happens. In Finder, ⌘X on selected files becomes ⌘C, and the next ⌘V becomes ⌥⌘V ("Move Item Here"), so ⌘Z still undoes the move. It leaves keys alone outside Finder, while you're renaming a file or typing in a search box, and once you copy something else. The scissors icon fills in while a cut is waiting to be pasted.

## Build and install

```bash
./build.sh
cp -R "build/Finder Cut.app" /Applications/
```

`build.sh` runs a self-test of the decision logic (`--selftest`) and signs with the Apple Development certificate, so the Accessibility permission survives rebuilds. The first run asks for Accessibility access (System Settings → Privacy & Security → Accessibility). Open at Login is switched on the first time the app runs, and you can turn it off from the menu.
