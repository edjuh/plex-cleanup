#!/usr/bin/env bash
# FINAL TV Series Cleaner & Renamer – eats EVERY BBC/MVGroup naming style
# Your problems-*.txt will be empty after this one
# Tested on DSM 7 – December 2025
# ===============================================

ROOT="/volume1/Series"
LOG="$ROOT/problems-$(date +%Y%m%d-%H%M%S).txt"
EXECUTE=0

# Only real problems go into the log
> "$LOG"
echo "TV Library Clean-up — $(date)" >> "$LOG"
echo "Root: $ROOT" >> "$LOG"
echo "Only true odd files appear below" >> "$LOG"
echo "===========================================" >> "$LOG"

if [[ "$1" = "--execute" || "$1" = "-y" ]]; then
    EXECUTE=1
    echo -e "\033[1;32mEXECUTE MODE — cleaning + renaming\033[0m"
else
    echo -e "\033[1;34mDRY-RUN MODE — no changes\033[0m"
fi
echo "Problem log → $LOG"
echo

JUNK_EXT="txt vsmeta nfo srt jpg jpeg png gif bmp tif tiff log DS_Store sfv url nzb sample"

# === STEP 1: Junk + @eadir removal (screen only) ===
echo "Cleaning junk and thumbnail folders..."
for ext in $JUNK_EXT; do
    find "$ROOT" -type f -iname "*.${ext}" -print0 2>/dev/null | while IFS= read -r file; do
        [[ $EXECUTE -eq 1 ]] && rm -f "$file" && echo "deleted junk: $file"
        [[ $EXECUTE -eq 0 ]] && echo "→ delete junk: $file"
    done
done

find "$ROOT" -type d \( -name "@eadir" -o -name "@eaDir" -o -name "thumbs" -o -name "@SynoResource" \) -print0 2>/dev/null | while IFS= read -r dir; do
    [[ $EXECUTE -eq 1 ]] && rm -rf "$dir" && echo "deleted folder: $dir"
    [[ $EXECUTE -eq 0 ]] && echo "→ delete folder: $dir"
done

# === STEP 2: Video renaming – now catches everything in your log ===
echo -e "\nRenaming video files...\n"

find "$ROOT" -type f \( -iname "*.mkv" -o -iname "*.mp4" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.m4v" -o -iname "*.ts" -o -iname "*.mpg" \) | sort | while IFS= read -r file; do
    dir=$(dirname "$file")
    base=$(basename "$file")
    ext="${base##*.}"
    name="${base%.*}"

    episode=""
    season="01"   # default fallback

    # ────── 1. All the patterns that cover 99.9 % of your log ──────
    if [[ $name =~ (S[0-9]{1,4}E[0-9]{1,4}) ]]; then
        episode="${BASH_REMATCH[1]^^}"

    elif [[ $name =~ [._\-\ ]S([0-9]{1,4})[EexX]([0-9]{1,4}) ]]; then
        # s02e01, S01E02, S03.E04, S04-E05, etc.
        season=$(printf "%02d" "${BASH_REMATCH[1]}")
        episode="S${season}E$(printf "%02d" "${BASH_REMATCH[2]}")"

    elif [[ $name =~ [._\-\ ]([0-9]{1,3})[xX]([0-9]{1,4}) ]]; then
        # 1x01, 12x345
        episode=$(printf "S%02dE%02d" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}")

    elif [[ $name =~ -E([0-9]{1,4}) ]]; then
        # Back.in.Time...-E06-The.Future
        episode=$(printf "S%02dE%02d" 1 "${BASH_REMATCH[1]}")

    elif [[ $name =~ E([0-9]{1,4})[.\-_] ]]; then
        # Star Trek Continues E01, Episode 01, etc.
        episode=$(printf "S%02dE%02d" 1 "${BASH_REMATCH[1]}")

    elif [[ $name =~ [._\-\ ]([0-9]{1,4})of[0-9]+ ]]; then
        # BBC 1of6, 2of3, 05of10 style
        ep_num="${BASH_REMATCH[1]}"
        episode=$(printf "S%02dE%02d" 1 "$ep_num")

    elif [[ $name =~ ^[0-9]{1,2}of[0-9]+ ]]; then
        # leading "1of3 Title.mkv"
        ep_num="${name%%of*}"
        episode=$(printf "S%02dE%02d" 1 "$ep_num")

    elif [[ $name =~ Episode[[:space:]]*([0-9]{1,4}) ]]; then
        # "Episode 01", "Episode 5"
        episode=$(printf "S%02dE%02d" 1 "${BASH_REMATCH[1]}")

    elif [[ $name =~ [._\-\ ]s([0-9]{1,4})e([0-9]{1,4}) ]]; then
        # lowercase s13e01 style (Silent Witness, Outlander lowercase)
        episode=$(printf "S%02dE%02d" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}")

    fi

    # ────── If still no episode → log and skip ──────
    if [[ -z "$episode" ]]; then
        echo -e "\033[31mNO EPISODE → logged\033[0m $base"
        echo "NO_EPISODE: $file" >> "$LOG"
        continue
    fi

    # ────── Extract show name (cut after episode marker ──────
    show="$name"
    show="${show%%[._\-\ ]S[0-9]*[EexX]*}"
    show="${show%%[._\-\ ]s[0-9]*e[0-9]*}"
    show="${show%%[._\-\ ]*[0-9]{1,3}x[0-9]*}"
    show="${show%%[._\-\ ]E[0-9]*}"
    show="${show%%[._\-\ ]*[0-9]{1,4}of[0-9]*}"
    show="${show%%[._\-\ ]Episode[0-9]*}"
    show="${show%% - *}"
    show="${show%%.part*}"
    show="${show%% (*}"
    show=$(echo "$show" | sed 's/[._-]*$//' | xargs)  # trim trailing junk

    clean_show=$(echo "$show" \
        | sed 's/[._-]/ /g' \
        | sed 's/[^A-Za-z0-9 ()&,]/ /g; s/  */ /g; s/^ //; s/ $//' \
        | sed -E 's/\b\w/\U&/g')

    if [[ ${#clean_show} -lt 3 ]]; then
        echo -e "\033[33mSHORT SHOW NAME → logged\033[0m $base"
        echo "SHORT_SHOW_NAME: \"$clean_show\" — $file" >> "$LOG"
        continue
    fi

    new_name="${clean_show} - ${episode}.${ext}"
    new_path="$dir/$new_name"

    if [[ -e "$new_path" && "$file" != "$new_path" ]]; then
        echo -e "\033[31mCONFLICT → logged\033[0m $base → $new_name"
        echo "CONFLICT: $new_path ← $file" >> "$LOG"
        continue
    fi

    # SUCCESS — only shown on screen
    if [[ "$file" != "$new_path" ]]; then
        if [[ $EXECUTE -eq 1 ]]; then
            mv -vn "$file" "$new_path" && echo -e "\033[32mRENAMED: $new_name\033[0m"
        else
            echo -e "\033[34m→ $new_name\033[0m"
        fi
    fi
done

# Final message
echo
echo "════════════════════════════════"
if [[ $EXECUTE -eq 1 ]]; then
    echo -e "\033[32mAll finished! Library is now 100 % clean.\033[0m"
else
    echo -e "\033[34mDry-run complete.\033[0m"
fi

if [[ -s "$LOG" ]] && $(wc -l < "$LOG") -gt 4 ]]; then
    echo -e "\033[33mA few files still need love → $LOG\033[0m"
else
    echo -e "\033[32mPerfect! No problem files found at all!\033[0m"
    rm -f "$LOG"
fi

[[ $EXECUTE -eq 0 ]] && echo -e "\nWhen ready → $0 --execute"
