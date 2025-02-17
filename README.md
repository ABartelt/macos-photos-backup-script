# macOS System Backup Script

A comprehensive backup solution for macOS systems that handles Photos libraries, iCloud Drive, contacts, development projects, and system configurations. The script provides a robust, incremental backup system with progress tracking and error handling.

## Features

- 📸 **Photos Library Backup**
  - Batch processing for large libraries
  - Progress tracking with time estimates
  - Automatic retry mechanism with batch size adjustment
  - Incremental backup support

- ☁️ **iCloud Drive Backup**
  - Complete sync of iCloud Drive contents
  - Excludes temporary and system files
  - Preserves folder structure

- 👥 **Contacts Backup**
  - Exports contacts to vCard format
  - Creates compressed archives
  - Maintains backup history

- 🗂️ **Projects Backup**
  - Backs up development projects
  - Excludes common development artifacts (node_modules, .git, etc.)
  - Configurable exclusion patterns

- ⚙️ **Configuration Backup**
  - System configuration files (.zshrc, .gitconfig, etc.)
  - Application settings (.config directory)
  - Shell scripts and utilities (.bin directory)
  - Homebrew package list (Brewfile)
  - SSH configurations

## Prerequisites

- macOS operating system
- External backup drive mounted at `/Volumes/My Passport`
- Homebrew (optional, for package list backup)
- rsync (typically pre-installed on macOS)
- bash 3.2 or later

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/yourusername/macos-backup.git
   cd macos-backup
   ```

2. Make the script executable:
   ```bash
   chmod +x backup_full.sh
   ```

3. Customize the backup paths in the script configuration section if needed:
   ```bash
   PHOTOS_LIBRARY="$HOME/Pictures/Photos Library.photoslibrary"
   PHOTOS_BACKUP_ROOT="/Volumes/My Passport/photos"
   # ... other paths
   ```

## Usage

### Basic Usage

Run a full system backup:
```bash
./backup_full.sh
```

### Command Line Options

- `--new`: Force a new photos backup without considering previous backup date
- `--resume`: Resume a previously interrupted photos backup
- `--photos-only`: Only backup Photos library
- `--icloud-only`: Only backup iCloud Drive
- `--contacts-only`: Only backup Contacts
- `--projects-only`: Only backup projects directory
- `--config-only`: Only backup configuration files
- `--help`: Show help message

### Examples

Backup only configuration files:
```bash
./backup_full.sh --config-only
```

Resume an interrupted photos backup:
```bash
./backup_full.sh --resume --photos-only
```

## Backup Structure

### Photos Backup
- Location: `/Volumes/My Passport/photos/`
- Maintains original photo metadata
- Creates date-stamped directories for incremental backups

### iCloud Backup
- Location: `/Volumes/My Passport/icloud_backup/`
- Mirrors iCloud Drive structure
- Excludes temporary files and .DS_Store

### Contacts Backup
- Location: `/Volumes/My Passport/contacts/`
- Format: vCard (.vcf)
- Compressed archives with date stamps
- Retains last 5 backups

### Projects Backup
- Location: `/Volumes/My Passport/projects_backup/`
- Date-stamped directories
- Excludes:
  - .git directories
  - node_modules
  - Python virtual environments
  - Compiled Python files
  - .DS_Store files

### Configuration Backup
- Location: `/Volumes/My Passport/config_backup/`
- Includes:
  - Shell configuration (.zshrc, .bashrc)
  - Git configuration
  - SSH settings
  - Custom scripts (.bin directory)
  - Application configs (.config directory)
  - Homebrew package list
- Removes dot prefixes in archive for better readability
- Excludes socket files and logs
- Retains last 5 backups

## Error Handling

- Validates backup drive presence
- Retries failed photo exports with reduced batch size
- Tracks and reports backup status for each component
- Provides detailed error messages and warnings
- Creates logs with timestamps for debugging

## Maintenance

The script automatically maintains backup history by:
- Keeping the last 5 backups for contacts and configurations
- Cleaning up temporary files after backup
- Removing old backup archives
- Managing incremental backups for photos

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Inspired by various macOS backup solutions
- Uses native macOS tools and APIs
- Built with shell scripting best practices

## Support

For support, please:
1. Check the existing issues
2. Review the README thoroughly
3. Create a new issue with:
   - Your macOS version
   - Error messages if any
   - Steps to reproduce the problem

## Disclaimer

Always test the backup script with a small subset of data first. While the script includes safety checks, it's recommended to verify the backed-up data after running the script for the first time.
