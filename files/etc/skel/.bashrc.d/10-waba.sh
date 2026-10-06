# Sourced by every new user's bash on waba bootc desktops.
# Keep it minimal — this lands in BOTH dev and admin images.
export EDITOR="${EDITOR:-nvim}"

# Handy bootc aliases
alias bootc-status='bootc status'
alias bootc-switch-dev='sudo bootc switch quay.io/waba/dev-desktop:latest'
alias bootc-switch-admin='sudo bootc switch quay.io/waba/admin-desktop:latest'
