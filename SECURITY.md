# Security policy

TypeStats reads every key press and mouse click on your Mac (it needs Input Monitoring
permission to do that), so a flaw in it matters. Please report problems privately.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting: open the repository's **Security** tab and choose
**Report a vulnerability**. Do not open a public issue for a security problem.

Include what you found, how to reproduce it, and which version you ran
(`defaults read /Applications/TypeStats.app/Contents/Info.plist CFBundleShortVersionString`).
You should get a first reply within a week.

## What counts

Anything that breaks the app's privacy promise is in scope, for example:

- a key code, character, typed text or click position written to disk, logged or sent anywhere;
- network activity outside the [documented privacy policy](README.md#privacy);
- the event tap modifying or blocking events (it is listen-only);
- counting while paused or in an excluded app.

## Supported versions

Only the latest release gets fixes.
