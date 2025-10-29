# 🖥️ open-on-screen.sh

A simple Bash script to open a browser (Brave, Chrome, Chromium, or Firefox)
in **kiosk fullscreen mode** on a specific **monitor** under **X11**.

It automatically:
- Detects your monitors (`xrandr --listmonitors`)
- Forces **X11 mode** (no Wayland, no keyring)
- Starts the browser in **kiosk / fullscreen**
- Disables *first-run*, *default browser* and *analytics prompts*
- Positions the window on the specified display

---

## 🧩 Requirements (Ubuntu)

### 1. Disable Wayland

This script requires **X11** (not Wayland).
To disable Wayland on Ubuntu:

```bash
sudo nano /etc/gdm3/custom.conf
```

Then **uncomment** or **add** this line:
```
WaylandEnable=false
```

Save, exit (`Ctrl+O`, `Ctrl+X`) and **reboot** your machine:
```bash
sudo reboot
```

After reboot, verify that X11 is active:
```bash
echo $XDG_SESSION_TYPE
```
✅ You should see `x11`.

---

### 2. Install required packages

Install the tools used by the script:
```bash
sudo apt update
sudo apt install -y x11-xserver-utils xdotool wmctrl
```

Optional (if you plan to use Brave or Chrome):
```bash
sudo apt install -y brave-browser
# or
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo apt install ./google-chrome-stable_current_amd64.deb
```

Or using the official Google repository:
```bash
wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list
sudo apt update
sudo apt install -y google-chrome-stable
```

You can also use Chromium or Firefox from Ubuntu repositories:
```bash
sudo apt install -y chromium-browser firefox
```

---

### 3. Download or create the script

Save the file as `open-on-screen.sh`:

```bash
nano open-on-screen.sh
```

Paste the full script (see project repository) and make it executable:

```bash
chmod +x open-on-screen.sh
```

---

### 4. Check your monitors

Use `xrandr` to list all monitors and their indexes:

```bash
xrandr --listmonitors
```

Example output:
```
Monitors: 2
 0: +*HDMI-1 3840/610x2160/350+0+0  HDMI-1
 1: +HDMI-2 1920/530x1080/300+3840+0  HDMI-2
```

In this case:
- Monitor **#1** = HDMI-1
- Monitor **#2** = HDMI-2

---

### 5. Run the script

#### 🦁 Brave
```bash
./open-on-screen.sh 1 brave http://localhost:8080
```

#### 🧭 Google Chrome / Chromium
```bash
./open-on-screen.sh 2 chrome https://example.com
```

#### 🦊 Firefox
```bash
./open-on-screen.sh 1 firefox https://mozilla.org
```

---

### 6. Notes

✅ **No password / keyring prompt**
The script uses `--password-store=basic` and isolated user profiles (`~/.kiosk-<browser>-<index>`).

✅ **No "default browser" prompt**
Flags `--no-first-run` and `--no-default-browser-check` are set.

✅ **Brave analytics popup disabled**
The script pre-creates preference files with:
```json
"brave": { "p3a": { "enabled": false, "notice_acknowledged": true } }
```

✅ **Window placement**
The browser window is moved and resized automatically to match the chosen monitor geometry.

---

### 7. Troubleshooting

**Check if X11 is active:**
```bash
echo $XDG_SESSION_TYPE
```
Should output `x11`.

**Check available monitors:**
```bash
xrandr --listmonitors
```

**If browser doesn’t appear:**
Try running with debug mode:
```bash
bash -x ./open-on-screen.sh 1 brave http://localhost:8080
```

**To exit kiosk mode:**
Use `Alt + F4` or `Alt + Tab` to switch and close the window manually.

---

### 🧰 Tested on

- Ubuntu 24.04 LTS
- Brave 1.77+
- Google Chrome 129+
- Chromium 129+
- Firefox 130+

---

### ⚙️ Optional

If you want the script to run automatically at startup, you can add it to your user’s **autostart**:

```bash
mkdir -p ~/.config/autostart
cat > ~/.config/autostart/open-on-screen.desktop <<EOF
[Desktop Entry]
Type=Application
Exec=/home/$USER/open-on-screen.sh 1 brave http://localhost:8080
X-GNOME-Autostart-enabled=true
Name=Kiosk Display
EOF
```

---

### 🏁 License

MIT License — free to use and modify.
