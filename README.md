# Project Backup Tools

<div align="center">
  <img src="https://raw.githubusercontent.com/Sajedur0/Project-Backup-Tools/main/windows/runner/resources/app_icon.ico" alt="App Icon" width="120" height="120" />
  <br/>
  <h3>Project Backup Tools</h3>
  <p>A modern Flutter desktop application to backup your development projects with one click.</p>
</div>

![Flutter](https://img.shields.io/badge/Flutter-3.x-blue)
![Platform](https://img.shields.io/badge/Platform-Windows-green)
![Version](https://img.shields.io/badge/Version-1.0.2-orange)

---

## Features

- Project Scanner - Automatically detects Flutter, Android, and web projects
- Smart Backup - Creates timestamped ZIP backups with progress tracking
- Backup History - View, manage, and delete previous backups
- Exclusions List - Skips unnecessary folders (`build`, `.dart_tool`, `node_modules`, etc.)
- Folder Picker - Choose any projects directory and backup destination
- Material 3 UI - Clean, modern interface with purple accent theme
- Open Backup Location - Jump directly to backup folder in Windows Explorer

---

## How It Works

1. Select your **Projects Folder** (default: `%USERPROFILE%\AndroidStudioProjects`)
2. Choose a **Backup Destination**
3. Pick a project from the list
4. Click **Start Backup**
5. Monitor progress via the progress dialog
6. Access backup history anytime from the top-right icon

---

## Tech Stack

| Package | Purpose |
|---------|---------|
| `file_picker` | Folder selection dialogs |
| `archive` | ZIP archive creation |
| `xml` | AndroidManifest.xml parsing |
| `yaml` | pubspec.yaml parsing |
| `process_run` | Execute shell commands |
| `path` | Cross-platform path handling |

---

## Build

```bash
flutter clean
flutter pub get
flutter build windows --release
```

Release artifacts are located at:

```
build/windows/x64/runner/Release/
├── flutter_project_backup_tool.exe
├── flutter_windows.dll
└── data/
    ├── app.so
    └── flutter_assets/
```

---

## Screenshots

### Projects View
<img width="800" src="assets/Project Backup Tools 1.png" alt="Projects View" />

### Backup in Progress
<img width="800" src="assets/Project Backup Tools 2.png" alt="Backup Progress" />

### Backup History
<img width="800" src="assets/Project Backup Tools 3.png" alt="History View" />

---

## Developer

**Sajedur Rahman Roni**

| Platform | Handle |
|----------|--------|
| GitHub | [Sajedur0](https://github.com/Sajedur0) |
| Facebook | [Sajedur0](https://facebook.com/Sajedur0) |

---

## Contributing

Contributions are welcome! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

Built with Flutter
