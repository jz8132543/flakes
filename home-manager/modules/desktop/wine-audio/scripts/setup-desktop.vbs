Option Explicit

Dim shell, filesystem, desktop, shortcut, target

Sub CheckError(stage, number, description)
    If number <> 0 Then
        WScript.Echo stage & ": " & number & " " & description
        WScript.Quit 1
    End If
    Err.Clear
End Sub

Set shell = CreateObject("WScript.Shell")
Set filesystem = CreateObject("Scripting.FileSystemObject")

' Keep the Wine desktop inside this prefix, not the Linux user's desktop.
desktop = "C:\AudioDesktop"
If Not filesystem.FolderExists(desktop) Then filesystem.CreateFolder desktop
shell.RegWrite "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders\Desktop", desktop, "REG_SZ"
shell.RegWrite "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders\Desktop", desktop, "REG_EXPAND_SZ"
shell.RegWrite "HKCU\Software\Wine\Explorer\Desktops\D-274\EnableShell", 1, "REG_DWORD"

On Error Resume Next
Set shortcut = shell.CreateShortcut(desktop & "\My Computer.lnk")
CheckError "CreateShortcut", Err.Number, Err.Description
target = shell.ExpandEnvironmentStrings("%SystemRoot%\system32\winefile.exe")
CheckError "ExpandEnvironmentStrings", Err.Number, Err.Description
shortcut.TargetPath = target
CheckError "TargetPath", Err.Number, Err.Description
shortcut.Arguments = "::{20D04FE0-3AEA-1069-A2D8-08002B30309D}"
CheckError "Arguments", Err.Number, Err.Description
shortcut.Save
CheckError "Save", Err.Number, Err.Description
If Not filesystem.FileExists(desktop & "\My Computer.lnk") Then WScript.Quit 1
WScript.Echo "Wine D-274 desktop: My Computer shortcut prepared."
