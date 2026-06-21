Set objShell = CreateObject("WScript.Shell")
objShell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""C:\Users\elaim\.openclaw\openclaw-tray.ps1""", 0, False
