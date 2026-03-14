#!/bin/sh

# insppired by: https://github.com/doomemacs/doomemacs/blob/ac649cce2abd1eb9d6d3f161928f9a7665b63310/modules/config/default/%2Bevil-bindings.el#L4

menu="${1:-root}"
self="$HOME/.config/tmux/menus/doomux.sh"

spawn_tool() {
  if command -v "$1" >/dev/null 2>&1; then
    tmux new-window -c "#{pane_current_path}" "$1"
  else
    tmux display-message "doomux: command not found: $1"
    return 1
  fi
}

spawn_first() {
  for cmd in "$@"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      tmux new-window -c "#{pane_current_path}" "$cmd"
      return 0
    fi
  done
  tmux display-message "doomux: command not found: $*"
  return 1
}

case "$menu" in
  root)
    tmux display-menu -T "tmux" -x R -y P \
      "Yazi" . "run-shell 'sh $self act-yazi'" \
      "" "" "" \
      "Buffers" b "run-shell 'sh $self buffers'" \
      "Windows" w "run-shell 'sh $self windows'" \
      "Git" g "run-shell 'sh $self git'" \
      "AI agents" a "run-shell 'sh $self ai'" \
      "Dev tools" d "run-shell 'sh $self tools'" \
      "Workmux" t "run-shell 'sh $self workmux'"
    ;;
  buffers)
    tmux display-menu -T "tmux buffers" -x R -y P \
      "List buffers/windows" b "choose-tree -Zw" \
      "Kill pane process (keep window)" k "respawn-pane -k -c '#{pane_current_path}'"
    ;;
  windows)
    tmux display-menu -T "tmux windows" -x R -y P \
      "Focus west" n "select-pane -L" \
      "Focus south" e "select-pane -D" \
      "Focus north" i "select-pane -U" \
      "Focus east" o "select-pane -R" \
      "" "" "" \
      "Move west" N "swap-pane -L" \
      "Move south" E "swap-pane -D" \
      "Move north" I "swap-pane -U" \
      "Move east" O "swap-pane -R" \
      "" "" "" \
      "Split vertical" v "split-window -h -c '#{pane_current_path}'" \
      "Split horizontal" h "split-window -v -c '#{pane_current_path}'" \
      "Kill window" q "kill-window"
    ;;
  git)
    tmux display-menu -T "tmux git" -x R -y P \
      "Tig" t "run-shell 'sh $self act-tig'" \
      "Magit (emacsclient -nw)" g "run-shell 'sh $self act-magit'" 
    ;;
  ai)
    tmux display-menu -T "tmux ai" -x R -y P \
      "Opencode" o "run-shell 'sh $self act-opencode'" \
      "Claude" c "run-shell 'sh $self act-claude'" \
      "Copilot CLI" p "run-shell 'sh $self act-copilot'" \
      "Codex" x "run-shell 'sh $self act-codex'" \
      "" "" "" \
      "More AI tools" m "run-shell 'sh $self ai-more'" \
      "Spec/workflow tools" s "run-shell 'sh $self ai-workflow'"
    ;;
  ai-more)
    tmux display-menu -T "tmux ai more" -x R -y P \
      "Amp" a "run-shell 'sh $self act-amp'" \
      "Crush" r "run-shell 'sh $self act-crush'" \
      "Forge" f "run-shell 'sh $self act-forge'" \
      "Cursor Agent" u "run-shell 'sh $self act-cursor-agent'" \
      "ECA" e "run-shell 'sh $self act-eca'" \
      "KiloCode" k "run-shell 'sh $self act-kilocode'" \
      "Letta" l "run-shell 'sh $self act-letta'" \
      "NanoCoder" n "run-shell 'sh $self act-nanocoder'" \
      "Pi" i "run-shell 'sh $self act-pi'" \
      "Catnip" t "run-shell 'sh $self act-catnip'" \
      "Claudebox" b "run-shell 'sh $self act-claudebox'" \
      "CCStatusline" c "run-shell 'sh $self act-ccstatusline'" \
      "Workmux" w "run-shell 'sh $self act-workmux'"
    ;;
  ai-workflow)
    tmux display-menu -T "tmux ai workflow" -x R -y P \
      "OpenSpec" o "run-shell 'sh $self act-openspec'" \
      "Beads_viewer (bv)" d "run-shell 'sh $self act-bv'" \
      "Vibe Kanban" v "run-shell 'sh $self act-vibe-kanban'" \
      "TUI Code Review (tuicr)" r "run-shell 'sh $self act-tuicr'" \
      "CK helper" k "run-shell 'sh $self act-ck'"
    ;;
  tools)
    tmux display-menu -T "tmux tools" -x R -y P \
      "Yazi" y "run-shell 'sh $self act-yazi'" \
      "Btop" b "run-shell 'sh $self act-btop'" \
      "Dust" d "run-shell 'sh $self act-dust'" \
      "Just" j "run-shell 'sh $self act-just'" \
      "Make" m "run-shell 'sh $self act-make'"
    ;;
  workmux)
    tmux display-menu -T "workmux" -x R -y P \
      "Dashboard"           d "new-window -c '#{pane_current_path}' 'workmux dashboard'" \
      "List worktrees"      l "new-window -c '#{pane_current_path}' 'workmux list'" \
      "Agent status"        s "new-window -c '#{pane_current_path}' 'workmux status'" \
      "" "" "" \
      "Add worktree..."     a "command-prompt -p 'Branch:' \"run-shell 'workmux add %%'\"" \
      "Open worktree..."    o "command-prompt -p 'Branch:' \"run-shell 'workmux open %%'\"" \
      "Close window..."     c "command-prompt -p 'Branch:' \"run-shell 'workmux close %%'\"" \
      "Merge + cleanup..."  m "command-prompt -p 'Branch:' \"new-window -c '#{pane_current_path}' 'workmux merge %%'\"" \
      "Remove (no merge)..." r "command-prompt -p 'Branch:' \"new-window -c '#{pane_current_path}' 'workmux remove %%'\"" \
      "" "" "" \
      "Send to agent..."    e "command-prompt -p 'Branch:' \"new-window -c '#{pane_current_path}' 'workmux send %% -e'\"" \
      "Capture output..."   p "command-prompt -p 'Branch:' \"new-window -c '#{pane_current_path}' 'workmux capture %%'\"" \
      "" "" "" \
      "Init .workmux.yaml"  i "new-window -c '#{pane_current_path}' 'workmux init'" \
      "Docs"                . "new-window -c '#{pane_current_path}' 'workmux docs'"
    ;;
  act-yazi)
    spawn_tool yazi
    ;;
  act-tig)
    spawn_tool tig
    ;;
  act-magit)
    tmux new-window -c "#{pane_current_path}" "TERM=xterm-24bits emacsclient -a "" -nw -e -q '(progn (magit-status))'"
    ;;
  act-opencode)
    spawn_tool opencode
    ;;
  act-claude)
    spawn_first claude claude-code
    ;;
  act-copilot)
    spawn_tool copilot
    ;;
  act-codex)
    spawn_tool codex
    ;;
  act-amp)
    spawn_tool amp
    ;;
  act-crush)
    spawn_tool crush
    ;;
  act-forge)
    spawn_tool forge
    ;;
  act-cursor-agent)
    spawn_tool cursor-agent
    ;;
  act-eca)
    spawn_tool eca
    ;;
  act-kilocode)
    spawn_first kilocode kilocode-cli
    ;;
  act-letta)
    spawn_first letta letta-code
    ;;
  act-nanocoder)
    spawn_tool nanocoder
    ;;
  act-pi)
    spawn_tool pi
    ;;
  act-catnip)
    spawn_tool catnip
    ;;
  act-claudebox)
    spawn_tool claudebox
    ;;
  act-ccstatusline)
    spawn_tool ccstatusline
    ;;
  act-workmux)
    spawn_tool workmux
    ;;
  act-openspec)
    spawn_tool openspec
    ;;
  act-bv)
    spawn_tool bv
    ;;
  act-vibe-kanban)
    spawn_tool vibe-kanban
    ;;
  act-tuicr)
    spawn_tool tuicr
    ;;
  act-ck)
    spawn_tool ck
    ;;
  act-btop)
    spawn_tool btop
    ;;
  act-dust)
    spawn_tool dust
    ;;
  act-just)
    spawn_tool just
    ;;
  act-make)
    spawn_tool make
    ;;
  *)
    tmux display-message "doomux: unknown menu '$menu'"
    exit 1
    ;;
esac
