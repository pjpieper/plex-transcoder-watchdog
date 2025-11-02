# plex-transcoder-watchdog
This contains my service files for re-rolling my Plex container in the event that a "zombie" transcoder session occurs due to an app crash. It should check every 5 minutes and re-roll the container if a "zombie" session is found using the Plex API token.
