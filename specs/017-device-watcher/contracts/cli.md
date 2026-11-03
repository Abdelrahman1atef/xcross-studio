# CLI contract: `xcross devices --watch [--json]`

JSON (NDJSON on stdout, one line each):
```
{"v":1,"type":"devices","devices":[{"udid":"…","name":"iPhone","osVersion":"16.7.16","connection":"usb"}]}
{"v":1,"type":"notice","message":"The device service is not reachable; retrying…"}
{"v":1,"type":"devices","devices":[]}
```
A snapshot at start and after every change; the notice and an empty snapshot once per outage. Text:
```
iPhone  iOS 16.7.16  <udid>
- iPhone
+ iPhone (iOS 16.7.16)
The device service is not reachable; retrying…
```
Runs until Ctrl+C (exit 0).
