#!/bin/bash

# Configuration
PHOTOS_LIBRARY="$HOME/Pictures/Photos Library.photoslibrary"
PHOTOS_BACKUP_ROOT="/Volumes/My Passport/photos"
ICLOUD_PATH="$HOME/Library/Mobile Documents/com~apple~CloudDocs"  # Local iCloud Drive folder
ICLOUD_BACKUP_ROOT="/Volumes/My Passport/icloud_backup"
CONTACTS_BACKUP_ROOT="/Volumes/My Passport/contacts_backup"
PROJECTS_BACKUP_ROOT="/Volumes/My Passport/projects_backup"
CONFIG_BACKUP_ROOT="/Volumes/My Passport/config_backup"
TEMP_EXPORT="/tmp/photos_export"
LAST_BACKUP_FILE="$PHOTOS_BACKUP_ROOT/.last_backup"
STATE_FILE="$PHOTOS_BACKUP_ROOT/.backup_state"
PROGRESS_FILE="/tmp/photos_export_progress"
EXCLUDE_FILE="/tmp/icloud_exclude"
BATCH_SIZE=100  # Smaller initial batch size for large libraries
MAX_RETRIES=3   # Maximum number of retries per batch

# Help message
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --new             Force a new photos backup without considering previous backup date"
    echo "  --resume          Resume a previously interrupted photos backup"
    echo "  --photos-only     Only backup Photos library"
    echo "  --icloud-only     Only backup iCloud Drive"
    echo "  --contacts-only   Only backup Contacts"
    echo "  --projects-only   Only backup projects directory"
    echo "  --config-only     Only backup configuration files"
    echo "  --help            Show this help message"
    exit 0
}

# Parse command line arguments
FORCE_NEW=false
RESUME=false
PHOTOS_ONLY=false
ICLOUD_ONLY=false
CONTACTS_ONLY=false
PROJECTS_ONLY=false
CONFIG_ONLY=false

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --new) FORCE_NEW=true ;;
        --resume) RESUME=true ;;
        --photos-only) PHOTOS_ONLY=true ;;
        --icloud-only) ICLOUD_ONLY=true ;;
        --contacts-only) CONTACTS_ONLY=true ;;
        --projects-only) PROJECTS_ONLY=true ;;
        --config-only) CONFIG_ONLY=true ;;
        --help) show_help ;;
        *) echo "Unknown parameter: $1"; show_help ;;
    esac
    shift
done

# Print with emoji and timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1"
}

# Progress bar function
show_progress() {
    local current=$1
    local total=$2
    local width=50
    local progress=$((current * width / total))
    local percentage=$((current * 100 / total))
    
    printf "\r["
    for ((i=0; i<width; i++)); do
        if [ $i -lt $progress ]; then
            printf "="
        else
            printf " "
        fi
    done
    printf "] %3d%% (%d/%d)" $percentage $current $total
    show_time_estimate $current $total $START_TIME
}

# Time estimation function
show_time_estimate() {
    local current=$1
    local total=$2
    local start_time=$3
    local current_time=$(date +%s)
    local elapsed=$((current_time - start_time))
    
    if [ $current -gt 0 ]; then
        local items_per_sec=$(bc -l <<< "$current / $elapsed")
        local remaining_items=$((total - current))
        local remaining_secs=$(bc -l <<< "$remaining_items / $items_per_sec")
        local remaining_mins=$(bc -l <<< "$remaining_secs / 60")
        printf " (%.1f mins remaining)" $remaining_mins
    fi
}

# Photos backup function
backup_photos() {
    log "📸 Starting Photos backup..."
    
    # Create temporary export directory
    mkdir -p "$TEMP_EXPORT"
    
    # Create AppleScript for Photos export with progress
    create_export_script() {
        local after_date="$1"
        local start_index="$2"
        local batch_size="$3"
        local script_file="/tmp/photos_export.scpt"
        
        if [ -n "$after_date" ]; then
            # Script for incremental export with date checking
            cat > "$script_file" << EOL
tell application "Photos"
    set total_items to count of every media item
    if $start_index = 0 then
        do shell script "echo " & total_items & " > '$PROGRESS_FILE'"
    end if
    
    set end_index to $start_index + $batch_size
    if end_index > total_items then
        set end_index to total_items
    end if
    
    set thePhotos to {}
    set processed_items to $start_index
    set comparison_date to (current date) - (get time to date "$after_date")
    
    repeat with i from ($start_index + 1) to end_index
        try
            set theItem to media item i
            set processed_items to processed_items + 1
            do shell script "echo " & processed_items & " >> '$PROGRESS_FILE'"
            
            if date of theItem is greater than comparison_date then
                set end of thePhotos to theItem
            end if
        end try
    end repeat
    
    if length of thePhotos is greater than 0 then
        export thePhotos to POSIX file "$TEMP_EXPORT" with using originals
    end if
end tell
EOL
        fi
        
        echo "$script_file"
    }
    # Process photos in batches
    START_INDEX=0
    RETRY_COUNT=0
    START_TIME=$(date +%s)

    if [ ! "$RESUME" = true ] || [ ! -f "$PROGRESS_FILE" ]; then
        log "📸 Scanning Photos library in batches (total approx. 65,000 photos)..."
        
        osascript -e 'tell application "Photos" to count every media item' > "$PROGRESS_FILE"
        TOTAL=$(cat "$PROGRESS_FILE")
        log "📊 Confirmed total photos: $TOTAL"
        log "⚙️ Using batch size: $BATCH_SIZE photos per batch ($(($TOTAL / $BATCH_SIZE + 1)) batches total)"
        
        while [ $START_INDEX -lt $TOTAL ]; do
            BATCH_NUM=$((START_INDEX / $BATCH_SIZE + 1))
            TOTAL_BATCHES=$(($TOTAL / $BATCH_SIZE + 1))
            log "📸 Processing batch $BATCH_NUM of $TOTAL_BATCHES (starting at index $START_INDEX)..."
            script_file=$(create_export_script "$LAST_BACKUP" $START_INDEX $BATCH_SIZE)
            
            # Execute AppleScript with simple timeout handling
            log "📸 Running batch export..."
            {
                osascript "$script_file"
                echo $? > "/tmp/script_exit_status"
            } & 
            SCRIPT_PID=$!
            
            # Monitor progress
            SECONDS=0
            while kill -0 $SCRIPT_PID 2>/dev/null; do
                if [ $SECONDS -gt 300 ]; then
                    log "⚠️ Batch operation timed out after 300 seconds"
                    kill -9 $SCRIPT_PID 2>/dev/null
                    wait $SCRIPT_PID 2>/dev/null
                    RESULT=1
                    break
                fi
                
                if [ -f "$PROGRESS_FILE" ]; then
                    CURRENT=$(wc -l < "$PROGRESS_FILE")
                    CURRENT=$((CURRENT - 1))
                    show_progress $CURRENT $TOTAL
                fi
                sleep 1
            done
            
            # Get the exit status if process completed normally
            if [ -f "/tmp/script_exit_status" ]; then
                RESULT=$(cat "/tmp/script_exit_status")
                rm -f "/tmp/script_exit_status"
            fi
            
            wait $SCRIPT_PID
            RESULT=$?
            
            if [ $RESULT -ne 0 ]; then
                ((RETRY_COUNT++))
                log "❌ Batch $BATCH_NUM failed (attempt $RETRY_COUNT of $MAX_RETRIES)"
                
                if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
                    BATCH_SIZE=$((BATCH_SIZE / 2))
                    RETRY_COUNT=0
                    log "⚙️ Reducing batch size to $BATCH_SIZE photos"
                    
                    if [ $BATCH_SIZE -lt 20 ]; then
                        log "❌ Export failed even with minimum batch size!"
                        rm -rf "$TEMP_EXPORT" "$script_file" "$PROGRESS_FILE"
                        return 1
                    fi
                fi
                sleep 5
                continue
            fi
            
            RETRY_COUNT=0
            START_INDEX=$((START_INDEX + BATCH_SIZE))
            echo
            sleep 2
        done
    fi

    # Update last backup timestamp
    date "+%Y-%m-%d" > "$LAST_BACKUP_FILE"
    rm -f "$STATE_FILE"

    # Cleanup
    rm -rf "$TEMP_EXPORT"

    log "✨ Photos backup completed successfully!"
    return 0
}

# iCloud Drive backup function
backup_icloud() {
    log "☁️ Starting iCloud Drive backup..."
    
    # Check if iCloud Drive path exists
    if [ ! -d "$ICLOUD_PATH" ]; then
        log "❌ iCloud Drive path not found: $ICLOUD_PATH"
        return 1
    fi

    # Create backup directory
    mkdir -p "$ICLOUD_BACKUP_ROOT"

    # Create exclude patterns
    cat > "$EXCLUDE_FILE" << EOL
.DS_Store
.Trash
.TemporaryItems
Icon?
EOL

    log "📂 Source: $ICLOUD_PATH"
    log "📂 Destination: $ICLOUD_BACKUP_ROOT"

    # Use rsync for the backup
    rsync -ah --progress --stats \
        --exclude-from="$EXCLUDE_FILE" \
        --delete \
        "$ICLOUD_PATH/" "$ICLOUD_BACKUP_ROOT/"

    if [ $? -eq 0 ]; then
        log "✨ iCloud Drive backup completed successfully!"
        BACKUP_SIZE=$(du -sh "$ICLOUD_BACKUP_ROOT" | cut -f1)
        log "📊 Total backup size: $BACKUP_SIZE"
        return 0
    else
        log "❌ iCloud Drive backup failed!"
        return 1
    fi
}

# Contacts backup function
backup_contacts() {
    log "👥 Starting Contacts backup..."
    
    # Create backup directory with date
    local backup_date=$(date +%Y%m%d)
    local backup_dir="$CONTACTS_BACKUP_ROOT/$backup_date"
    mkdir -p "$backup_dir"
    
    # Create temporary AppleScript for launching Contacts
    local launch_script="/tmp/launch_contacts.scpt"
    cat > "$launch_script" << EOL
tell application "Contacts"
    launch
    delay 2  -- Give the app some time to fully launch
end tell
EOL

    # Launch Contacts app
    log "📱 Launching Contacts app..."
    osascript "$launch_script"
    
    # Create temporary AppleScript for Contacts export
    local script_file="/tmp/contacts_export.scpt"
    cat > "$script_file" << EOL
tell application "Contacts"
    try
        set allPeople to every person
        set vcfData to ""
        repeat with onePerson in allPeople
            set vcfData to vcfData & (vcard of onePerson) & return
        end repeat
        return vcfData
    on error errMsg
        log errMsg
        return ""
    end try
end tell
EOL
    
    log "📇 Exporting contacts as vCard..."
    osascript "$script_file" > "$backup_dir/contacts.vcf"
    local export_result=$?
    
    # Quit Contacts app
    osascript -e 'tell application "Contacts" to quit'
    
    # Check if export was successful and file has content
    if [ $export_result -eq 0 ] && [ -f "$backup_dir/contacts.vcf" ] && [ -s "$backup_dir/contacts.vcf" ]; then
        log "📦 Creating contacts archive..."
        tar -czf "$backup_dir/contacts_backup.tar.gz" -C "$backup_dir" contacts.vcf
        
        # Keep only the last 5 backups
        log "🧹 Cleaning up old backups..."
        cd "$CONTACTS_BACKUP_ROOT"
        ls -t | tail -n +6 | xargs rm -rf 2>/dev/null
        
        log "✨ Contacts backup completed successfully!"
        BACKUP_SIZE=$(du -sh "$backup_dir" | cut -f1)
        log "📊 Contacts backup size: $BACKUP_SIZE"
        return 0
    else
        log "❌ Failed to export contacts or contacts file is empty!"
        rm -rf "$backup_dir"  # Clean up failed backup directory
        return 1
    fi
}

# Projects backup function
backup_projects() {
    log "🗂️  Starting Projects backup..."
    
    # Check if projects directory exists
    if [ ! -d "$HOME/projects" ]; then
        log "❌ Projects directory not found: $HOME/projects"
        return 1
    fi

    # Create backup directory with date
    local backup_date=$(date +%Y%m%d)
    local backup_dir="$PROJECTS_BACKUP_ROOT/$backup_date"
    mkdir -p "$backup_dir"

    log "📂 Backing up projects directory..."
    rsync -ah --progress --stats \
        --exclude ".git" \
        --exclude "node_modules" \
        --exclude "venv" \
        --exclude "__pycache__" \
        --exclude "*.pyc" \
        --exclude ".DS_Store" \
        "$HOME/projects/" "$backup_dir/"
    
    local rsync_result=$?
    
    if [ $rsync_result -eq 0 ]; then
        log "✨ Projects backup completed successfully!"
        BACKUP_SIZE=$(du -sh "$backup_dir" | cut -f1)
        log "📊 Projects backup size: $BACKUP_SIZE"
        
        # Keep only the last 5 backups
        log "🧹 Cleaning up old project backups..."
        cd "$PROJECTS_BACKUP_ROOT"
        ls -t | tail -n +6 | xargs rm -rf 2>/dev/null
        return 0
    else
        log "❌ Projects backup failed!"
        return 1
    fi
}

# Config backup function
# Config backup function
backup_config() {
    log "⚙️ Starting configuration backup..."
    
    # Create backup directory with date
    local backup_date=$(date +%Y%m%d)
    local backup_dir="$CONFIG_BACKUP_ROOT/$backup_date"
    mkdir -p "$backup_dir"
    
    # List of config files and directories to backup
    local config_items=(
        "$HOME/.zshrc"
        "$HOME/.bashrc"
        "$HOME/.vimrc"
        "$HOME/.gitconfig"
        "$HOME/.ssh/config"
        "$HOME/.config"
        "$HOME/.bin"
    )
    
    # Backup each config item
    for item in "${config_items[@]}"; do
        if [ -e "$item" ]; then
            log "📄 Backing up: $item"
            # Create parent directory structure without dot prefix for archive
            local rel_path="${item#$HOME/}"
            local archive_path="${rel_path#.}"  # Remove leading dot for archive
            local target_dir="$backup_dir/$(dirname "$archive_path")"
            mkdir -p "$target_dir"
            
            # Copy the item
            if [ -d "$item" ]; then
                rsync -ah --progress \
                    --exclude ".DS_Store" \
                    --exclude "*.log" \
                    --exclude "*.sock" \
                    --exclude "op-daemon.sock" \
                    "$item/" "$backup_dir/$(basename "$archive_path")/"
            else
                cp "$item" "$target_dir/$(basename "$archive_path")"
            fi
        else
            log "⚠️ Config item not found: $item"
        fi
    done

    # Backup Homebrew bundle
    if command -v brew >/dev/null 2>&1; then
        log "🍺 Creating Homebrew bundle dump..."
        # Create a temporary directory for Homebrew dump
        local brew_backup_dir="$backup_dir/homebrew"
        mkdir -p "$brew_backup_dir"
        
        # Dump package list
        HOMEBREW_NO_AUTO_UPDATE=1 brew bundle dump --file="$brew_backup_dir/Brewfile" --force
        
        # Get additional Homebrew information
        cd "$brew_backup_dir"
        brew list --full-name > brew_list.txt
        brew list --cask --full-name > brew_cask_list.txt
        brew tap > brew_taps.txt
        brew outdated > brew_outdated.txt 2>/dev/null
        
        # Create version info file
        {
            echo "Homebrew Package Versions"
            echo "========================"
            echo "Generated: $(date)"
            echo
            echo "Installed Packages:"
            brew list --versions
        } > brew_versions.txt
        
        cd - >/dev/null 2>&1 || true
    else
        log "⚠️ Homebrew not found, skipping bundle dump"
    fi
    
    log "📦 Creating config archive..."
    cd "$CONFIG_BACKUP_ROOT"
    
    # Create an archive with all contents, maintaining folder structure but without dot prefixes
    tar --exclude="*.sock" \
        -czf "$backup_dir.tar.gz" \
        -C "$backup_dir" \
        config \
        bin \
        homebrew \
        $(cd "$backup_dir" && find . -maxdepth 1 -type f -name "*rc" -o -name "gitconfig" | sed 's|^\./||')
    
    # Keep only the last 5 backups
    log "🧹 Cleaning up old config backups..."
    ls -t | grep "^[0-9]\{8\}.tar.gz$" | tail -n +6 | xargs rm -f 2>/dev/null
    rm -rf "$backup_dir"  # Remove the uncompressed backup
    
    if [ $? -eq 0 ]; then
        log "✨ Configuration backup completed successfully!"
        BACKUP_SIZE=$(du -sh "$backup_dir.tar.gz" | cut -f1)
        log "📊 Config backup size: $BACKUP_SIZE"
        return 0
    else
        log "❌ Configuration backup failed!"
        return 1
    fi
}

# Main execution logic
main() {
    # Check if any backup drive is mounted
    if [ ! -d "/Volumes/My Passport" ]; then
        log "❌ Backup drive not found! Please connect your backup drive."
        exit 1
    fi
    
    # Track overall success
    local success=true
    
    # Perform backups based on flags
    if [ "$PHOTOS_ONLY" = true ]; then
        backup_photos || success=false
    elif [ "$ICLOUD_ONLY" = true ]; then
        backup_icloud || success=false
    elif [ "$CONTACTS_ONLY" = true ]; then
        backup_contacts || success=false
    elif [ "$PROJECTS_ONLY" = true ]; then
        backup_projects || success=false
    elif [ "$CONFIG_ONLY" = true ]; then
        backup_config || success=false
    else
        # Full backup
        backup_photos || success=false
        backup_icloud || success=false
        backup_contacts || success=false
        backup_projects || success=false
        backup_config || success=false
    fi
    
    # Final status
    if [ "$success" = true ]; then
        log "✨ All backup operations completed successfully!"
        exit 0
    else
        log "⚠️ Some backup operations failed. Check the logs above for details."
        exit 1
    fi
}

# Run main function
main
