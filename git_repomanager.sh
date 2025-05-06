#!/opt/homebrew/bin/bash
#
# git_repo_manager.sh
#
# List → choose → clone-or-update GitHub repositories using your SSH key.
# If the GitHub CLI (`gh`) is installed *and* authenticated, we can see
# private repos too. Otherwise we fall back to the public‑only REST call.
#
# Requirements: bash 4+, git, jq, and (optionally) the GitHub CLI.
# Optional: curl (only needed for the public‑repo fallback).

set -euo pipefail

# -------- helpers ---------------------------------------------------------
die() { echo "❌  $*" >&2; exit 1; }

need() { command -v "$1" &>/dev/null || die "'$1' is required but not found."; }

# -------- tools check -----------------------------------------------------
need git
need jq

HAVE_GH=false
if command -v gh &>/dev/null; then
  if gh auth status -h github.com &>/dev/null; then
    HAVE_GH=true
  fi
fi

# -------- 1. prompt for user ---------------------------------------------
read -rp "GitHub username: " GH_USER
[[ -z "$GH_USER" ]] && die "No user name provided."

# -------- 2. fetch repo list ---------------------------------------------
declare -a REPOS
if $HAVE_GH; then
  echo "Using authenticated GitHub CLI to retrieve repositories…"
  # --source=all ⇒ include repos you own, collaborate on, or belong to via org
  mapfile -t REPOS < <(gh repo list "$GH_USER" --limit 200 --json nameWithOwner \
                       -q '.[].nameWithOwner' | sort)
else
  echo "GitHub CLI not available/authenticated — falling back to public repos."
  need curl
  REPO_JSON=$(curl -fsSL "https://api.github.com/users/$GH_USER/repos?per_page=200") \
    || die "Could not retrieve public repository list (rate‑limited?)."
  mapfile -t REPOS < <(echo "$REPO_JSON" | jq -r '.[].full_name' | sort)
fi

((${#REPOS[@]})) || die "No repositories found for '$GH_USER'."

# -------- 3. show menu ----------------------------------------------------
echo
echo "Available repositories:"
for i in "${!REPOS[@]}"; do
  printf "%3d) %s\n" $((i+1)) "${REPOS[$i]}"
done
echo
read -rp "Enter the number of the repo to clone/update: " SEL
[[ "$SEL" =~ ^[0-9]+$ ]] || die "Selection must be a number."
(( SEL >= 1 && SEL <= ${#REPOS[@]} )) || die "Number out of range."

CHOSEN="${REPOS[$((SEL-1))]}"
REPO_DIR=$(basename "$CHOSEN")

# -------- 4. clone or update ---------------------------------------------
if [[ -d "$REPO_DIR/.git" ]]; then
  echo "📂  '$REPO_DIR' already exists – pulling latest changes…"
  git -C "$REPO_DIR" pull --ff-only
else
  echo "⬇️  Cloning '$CHOSEN' into ./$REPO_DIR …"
  git clone "git@github.com:$CHOSEN.git"
fi

