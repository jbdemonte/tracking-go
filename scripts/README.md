# open-on-screen-fullscreen.sh

A shell script to open a browser on a specific **display** (screen) in **fullscreen or kiosk mode**,  
with optional per-screen browser profiles and auto camera/mic permissions.

Supports **Wayland** and **X11 (Xorg)** environments on Ubuntu.

---

## 🧭 Overview

This script was originally made for **Linux Lite (X11)** and now works on **Ubuntu (Wayland)** too.  
It automatically detects whether you’re running on **Wayland** or **Xorg**, and adapts:

- On **X11** → moves the window to the specified screen and fullscreen it (`wmctrl`).
- On **Wayland** → launches directly in **kiosk mode** (fullscreen, no bars) because Wayland doesn’t allow external window control.
- You can force X11 behavior on Wayland with `FORCE_X11=1`.

---

## 🛠️ Requirements

### System tools
Install the required X11 utilities (used only under Xorg):

```bash
sudo apt update
sudo apt install -y x11-xserver-utils wmctrl xdotool
```

### Check your session type
Run this command to know what you’re using:

```bash
echo $XDG_SESSION_TYPE
```

- If it prints `x11` → full window control works.
- If it prints `wayland` → only kiosk mode is possible unless you set `FORCE_X11=1`.

---

## 🌐 Browser installation

### 🦊 Firefox (recommended .deb version, not Snap)
Ubuntu installs Firefox as a **Snap** by default — this prevents external window control.  
Remove it and install the native `.deb` version:

```bash
sudo snap remove firefox
sudo add-apt-repository ppa:mozillateam/ppa
sudo apt update
sudo apt install -y firefox
```

---

### 🌍 Google Chrome

Official Google repository:
```bash
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list
sudo apt update
sudo apt install -y google-chrome-stable
```

---

### 🧭 Brave Browser

Official Brave repo:
```bash
sudo apt install -y curl
sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list
sudo apt update
sudo apt install -y brave-browser
```

---

### 💻 Microsoft Edge (optional)

```bash
wget -q https://packages.microsoft.com/keys/microsoft.asc -O- | sudo gpg --dearmor -o /usr/share/keyrings/microsoft-edge.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/microsoft-edge.gpg] https://packages.microsoft.com/repos/edge stable main" | sudo tee /etc/apt/sources.list.d/microsoft-edge.list
sudo apt update
sudo apt install -y microsoft-edge-stable
```

---

### ⚙️ Chromium

```bash
sudo snap install chromium
```

> ⚠️ Note: Chromium Snap cannot be controlled by `wmctrl` (sandboxed),  
> so only kiosk mode will work unless you switch to a .deb-based browser.

---

## 🚀 Usage

```bash
./open-on-screen-fullscreen.sh <url> [output_name] [browser_alias]
```

### Example

```bash
./open-on-screen-fullscreen.sh "http://localhost:8080" HDMI-1 chrome
```

### Browser aliases
You can use short names:
```
chrome, chromium, brave, firefox, vivaldi, edge
```

---

## 🖥️ How it works

- Detects the session type (`wayland` or `x11`).
- If X11: uses `xrandr` to find the screen geometry, launches the browser,  
  moves the window to the target display and makes it fullscreen using `wmctrl`.
- If Wayland: directly launches the browser in kiosk mode (`--kiosk`).

### Forcing X11 mode (under Wayland)
You can run:
```bash
FORCE_X11=1 ./open-on-screen-fullscreen.sh "https://example.com" HDMI-1 brave
```
This forces the browser to run under **XWayland** (`--ozone-platform=x11`) so `wmctrl` works again.

---

## 🧩 Exiting fullscreen / kiosk mode

| Browser                              | Mode                 | How to exit                                                             |
|--------------------------------------|----------------------|-------------------------------------------------------------------------|
| **Firefox**                          | `--kiosk`            | Press **Alt + F4** or run `pkill firefox`                               |
|                                      | `--fullscreen`       | Toggle with **F11**                                                     |
| **Chrome / Brave / Edge / Chromium** | `--kiosk`            | Press **Alt + F4** or run `pkill chrome` / `pkill brave` / `pkill edge` |
|                                      | `--start-fullscreen` | Toggle with **F11**                                                     |
| **All browsers**                     | Any                  | You can always close from terminal: `pkill <browser>`                   |

If you prefer a *quittable fullscreen* (normal fullscreen with F11),  
you can modify the script to replace `--kiosk` with `--start-fullscreen`.

---

## 🧰 Example: Debugging

List connected displays:
```bash
xrandr --query
```

Check your current session type:
```bash
echo $XDG_SESSION_TYPE
```

See what windows `wmctrl` detects:
```bash
wmctrl -lx
```

Check if a browser is running:
```bash
pgrep -a chrome
```

---

## ✅ Summary

| Environment                   | Behavior                                | Control               |
|-------------------------------|-----------------------------------------|-----------------------|
| **X11 (Xorg)**                | Full window control (move + fullscreen) | Works via `wmctrl`    |
| **Wayland (default Ubuntu)**  | Only kiosk mode (no window management)  | `--kiosk` only        |
| **FORCE_X11=1 under Wayland** | Runs browser under XWayland             | Full control restored |

---

## 💡 Tips

- If you run a minimal server (no desktop), install Xorg and Openbox:
  ```bash
  sudo apt install -y xorg openbox
  startx /usr/bin/openbox
  ```
- Each screen gets its own browser profile at:  
  `~/.browser-per-output/<browser>_<screen>/`

---

## 📜 License
MIT — feel free to use and modify.

---

## ✨ Author
Script originally designed for **Linux Lite**, updated for **Ubuntu + Wayland** support.
