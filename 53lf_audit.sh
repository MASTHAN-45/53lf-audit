#!/bin/bash

# ==============================================================================
# CONFIGURATION
# ==============================================================================
# By default, the script looks for custom tools in ~/tools.
# If a user keeps them elsewhere, they can change this path.
CUSTOM_TOOLS_DIR="$HOME/tools"
# ==============================================================================

GREEN=$(tput setaf 2)
RED=$(tput setaf 1)
YELLOW=$(tput setaf 3)
BLUE=$(tput setaf 4)
CYAN=$(tput setaf 6)
RESET=$(tput sgr0)

echo "${CYAN}"
cat << "EOF"
 ███████╗██████╗ ██╗     ███████╗    █████╗ ██╗   ██╗██████╗ ██╗████████╗
 ██╔════╝╚════██╗██║     ██╔════╝   ██╔══██╗██║   ██║██╔══██╗██║╚══██╔══╝
 ███████╗ █████╔╝██║     █████╗     ███████║██║   ██║██║  ██║██║   ██║
 ╚════██║ ╚═══██╗██║     ██╔══╝     ██╔══██║██║   ██║██║  ██║██║   ██║
 ███████║██████╔╝███████╗██║        ██║  ██║╚██████╔╝██████╔╝██║   ██║
 ╚══════╝╚═════╝ ╚══════╝╚═╝        ╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═╝   ╚═╝
EOF
echo "${RESET}"

# ---------------------------------------------------------
# PHASE 1: DYNAMIC BINARY HUNT & EXECUTION TEST
# ---------------------------------------------------------
echo "${YELLOW}[*] PHASE 1: Hunting and Testing Executables...${RESET}"
declare -a discovered_tools

search_dirs=("$HOME/go/bin" "$HOME/.local/bin" "/usr/local/bin" "/opt")

for dir in "${search_dirs[@]}"; do
    if [ -d "$dir" ]; then
        while IFS= read -r file; do
            discovered_tools+=("$file")
        done < <(find "$dir" -maxdepth 2 -type f -executable 2>/dev/null)
    fi
done

if [ -d "$CUSTOM_TOOLS_DIR" ]; then
    while IFS= read -r file; do
        discovered_tools+=("$file")
    done < <(find "$CUSTOM_TOOLS_DIR" -maxdepth 3 -type f -executable -not -path "*/.git/*" -not -path "*/Wordlists/*" 2>/dev/null)
fi

mapfile -t unique_tools < <(printf "%s\n" "${discovered_tools[@]}" | sort -u)

installed_working=0
installed_broken=0
ignored_garbage=0
broken_list=""

for tool_path in "${unique_tools[@]}"; do
    tool_name=$(basename "$tool_path")
    ext="${tool_name##*.}"

    if [ "$tool_name" = "$ext" ]; then
        ext=""
    fi

    if [[ "$tool_name" =~ ^(Dockerfile|LICENSE.*|.*\.md|.*\.txt|.*\.png|.*\.css|.*\.html|.*\.bin|.*\.js|.*\.csv)$ ]]; then
        ((ignored_garbage++))
        continue
    fi

    case "$ext" in
        py) timeout 2s python3 "$tool_path" -h < /dev/null > /dev/null 2>&1 ;;
        php) timeout 2s php "$tool_path" -h < /dev/null > /dev/null 2>&1 ;;
        pl) timeout 2s perl "$tool_path" -h < /dev/null > /dev/null 2>&1 ;;
        sh) timeout 2s bash "$tool_path" -h < /dev/null > /dev/null 2>&1 ;;
        *) timeout 2s "$tool_path" -h < /dev/null > /dev/null 2>&1 ;;
    esac

    status=$?

    if [ $status -eq 127 ] || [ $status -eq 126 ]; then
        echo "  ${RED}[!] $tool_name is BROKEN (Exit: $status)${RESET}"
        broken_list="$broken_list $tool_name"
        ((installed_broken++))
    else
        echo "  ${GREEN}[✓] $tool_name is FUNCTIONAL${RESET}"
        ((installed_working++))
    fi
done

total_valid_tools=$((installed_working + installed_broken))
echo ""
echo "  ${GREEN}[✓] Successfully tested $total_valid_tools actual tools (Ignored $ignored_garbage misconfigured text files).${RESET}"
echo ""

# ---------------------------------------------------------
# PHASE 2: CLONED REPOSITORY AUDIT
# ---------------------------------------------------------
echo "${YELLOW}[*] PHASE 2: Scanning Repositories...${RESET}"
repo_count=0
if [ -d "$CUSTOM_TOOLS_DIR" ]; then
    repo_count=$(find "$CUSTOM_TOOLS_DIR" -maxdepth 2 -type d | wc -l)
    echo "  ${GREEN}[✓] Found approximately $repo_count tool directories inside $CUSTOM_TOOLS_DIR${RESET}"
else
    echo "  ${YELLOW}[!] Custom tools directory ($CUSTOM_TOOLS_DIR) not found. Skipping repo count.${RESET}"
fi
echo ""

# ---------------------------------------------------------
# PHASE 3: DEEP HOME FOLDER WORDLIST SCAN
# ---------------------------------------------------------
echo "${YELLOW}[*] PHASE 3: Scanning Entire Home Directory for Wordlists (>1MB)...${RESET}"

# Scan the entire home directory AND system wordlist folders for text/dic files larger than 1 Megabyte
mapfile -t all_wordlists < <(find "$HOME" /usr/share/wordlists /usr/share/seclists /opt/SecLists -type f \( -name "*.txt" -o -name "*.dic" -o -name "*.csv" \) -size +1M 2>/dev/null | sort -u)

total_wordlists=${#all_wordlists[@]}

if [ $total_wordlists -gt 0 ]; then
    echo "  ${GREEN}[✓] Discovered $total_wordlists heavy payload dictionaries (files > 1MB).${RESET}"
    echo ""
    echo "${YELLOW}[*] Top 5 Largest Dictionaries Found System-Wide:${RESET}"
    printf "%s\n" "${all_wordlists[@]}" | xargs ls -lh 2>/dev/null | awk '{print $5, $9}' | sort -hr | head -n 5 | while read size name; do
      clean_name=$(basename "$name")
      echo "  ${GREEN}-> $clean_name ($size) [Path: $name]${RESET}"
    done
else
    echo "  ${RED}[!] No heavy wordlists (>1MB) found on this system.${RESET}"
fi
echo ""

# ---------------------------------------------------------
# FINAL AUDIT REPORT
# ---------------------------------------------------------
echo "${CYAN}======================================================${RESET}"
echo "${CYAN}                  FINAL AUDIT REPORT                  ${RESET}"
echo "${CYAN}======================================================${RESET}"
echo -e "Total Valid Tools Tested: ${YELLOW}$total_valid_tools${RESET}"
echo -e "Tools Working           : ${GREEN}$installed_working${RESET}"
echo -e "Tools Broken            : ${RED}$installed_broken${RESET}"
echo -e "Cloned Tool Folders     : ${GREEN}$repo_count${RESET}"
echo -e "Heavy Wordlist Files    : ${GREEN}$total_wordlists dictionaries (>1MB) ready${RESET}"
echo "${CYAN}======================================================${RESET}"
if [ $installed_broken -gt 0 ]; then
  echo "${RED}ACTION REQUIRED: The following tools are actually broken: $broken_list${RESET}"
else
  echo "${GREEN}ALL SYSTEMS GO. Happy Hunting.${RESET}"
fi
