# plex-transcoder-watchdog
This contains my service files for re-rolling my Plex container in the event that a "zombie" transcoder session occurs due to an app crash. It should check every 5 minutes and re-roll the container if a "zombie" session is found using the Plex API token.


Plex API Token goes here: /etc/plex-watchdog/env

Use:

```bash
sudo mkdir -p /etc/plex-watchdog
printf "PLEX_TOKEN=your_token_here" | sudo tee /etc/plex-watchdog/env >/dev/null
sudo chmod 600 /etc/plex-watchdog/env
```

Timer and Service files go here: /etc/systemd/system/

WatchDog Script goes here: /usr/local/bin/

Make sure to run: 
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now plex-transcode-watchdog.timer
``` 

Test run:

```bash
sudo systemctl start plex-transcode-watchdog.service
journalctl -u plex-transcode-watchdog.service -n 50 -e
```

Confirm with:

```bash
systemctl status plex-transcode-watchdog.timer
```