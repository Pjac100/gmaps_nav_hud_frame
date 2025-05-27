# Google Maps Turn-by-Turn Directions

Shows Google Maps turn-by-turn navigation notifications on the Frame (Android only, due to the requirement to read app notifications)

When a Google Maps navigation session is underway, on Android a persistent notification is running that shows some text (distance until next turn, next street name etc.) and a directional arrow icon.

Using the [notification_listener_service](https://github.com/iampawan/notification_listener_service) package (fork), this information is gathered from the notification each time the notification changes and is pushed to the Frame display. Android notification permission handling has changed over time - this app was developed and tested on Android 15 on a Pixel 7 Pro; configuration differences on your device might lead to issues.

The heads-up-display of turn-by-turn directions is only recommended for use while walking.

Background mode/phone screen off has not been tested. Display is only cleared on application "Stop", not on the floating action button cancel.

### Instructions
The app will attempt to connect, start and run on startup - but if Frame is not found:
Tap to wake Frame, Click "Connect" in the app to connect to Frame, "Start" to load the app to Frame, then click the navigation floating action button, then accept notification permissions to begin. The app will listen for Google Maps live navigation notifications from an existing or any new navigation session running on the host device and mirror the directions to the Frame display. (Existing live navigation sessions update the notification roughly every minute, so you might need to wait a minute for the first update. New navigation sessions should update right away.)

"Stop" and "Disconnect" after a session to remove application files from Frame and do a clean bluetooth disconnection from the host device.

### Frameshots
![Frameshot1](docs/frameshot1.jpg)

### Architecture
![Architecture](docs/Frame%20App%20Architecture%20-%20Google%20Maps%20Turn-by-Turn%20Directions.svg)
