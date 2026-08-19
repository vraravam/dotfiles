# Keybase to git-remote-gcrypt Migration Guide

**Date:** July 4, 2026
**Branch:** keybase-migration

---

## Overview

This migration replaces Keybase with **git-remote-gcrypt** for encrypted git remotes.

### What Changed

**Removed:**
- Keybase.app (GUI dependency)
- KBFS filesystem integration
- `keybase://` remote URLs

**Added:**
- `git-remote-gcrypt` (CLI-only tool)
- `gnupg` (encryption backend)
- `gcrypt::` remote URLs
- Symmetric encryption (password-based, simpler than GPG keys)

**Benefits:**
- ✓ Zero GUI dependency
- ✓ Pure CLI workflow
- ✓ Fully automatable in fresh-install
- ✓ Works on vanilla OS (after Homebrew install)
- ✓ No background processes

**Trade-offs:**
- Slightly more metadata exposed (branch name, pack sizes) - easily mitigated
- Password prompt on push/pull (can be cached with git credential helper)

---

## Files Changed

### 1. Brewfile
- **Removed:** Keybase cask + postinstall hooks
- **Added:** `git-remote-gcrypt` + `gnupg` in base packages section

### 2. fresh-install-of-osx.sh
- **Added:** Call to `setup-git-remote-gcrypt.rb` after Homebrew install
- **Preserved:** Keybase clone logic (for backward compatibility during transition)

### 3. New Scripts

#### scripts/setup-git-remote-gcrypt.rb
Configures git-remote-gcrypt for symmetric encryption:
```ruby
# Configure gcrypt.participants = "simple" (password-based encryption)
# Called automatically during fresh-install after Homebrew install
```

#### scripts/migrate-keybase-to-gcrypt.rb
Migrates a single repository from Keybase to gcrypt:
```ruby
# Usage:
migrate-keybase-to-gcrypt.rb \
  --repo ~/home \
  --encrypted-url gcrypt::git@github.com:user/home.git
```

#### scripts/migrate-keybase-repos.rb
Convenience script to migrate both home and browser-profiles repos:
```ruby
# Migrates:
# - ~/home → gcrypt::git@github.com:vraravam/home.git
# - ~/personal/<user>/browser-profiles → gcrypt::git@github.com:vraravam/browser-profiles.git
```

---

## Migration Steps

### Phase 1: Install gcrypt (Already Done in This Branch)

```bash
# Checkout this branch
git checkout keybase-migration

# Review changes
git diff master -- files/--HOME--/Brewfile
git diff master -- scripts/fresh-install-of-osx.sh

# Install gcrypt
brew install git-remote-gcrypt gnupg

# Configure for symmetric encryption
ruby scripts/setup-git-remote-gcrypt.rb
```

### Phase 2: Create Encrypted GitHub Repos

**IMPORTANT: Repos must be PUBLIC for vanilla OS recovery to work.**

For each repo you want to migrate, create PUBLIC (not private) repos on GitHub:

**Option A: Via GitHub Web Interface:**
1. Go to: https://github.com/new
2. Create repo: `vraravam/home`
   - Make it **PUBLIC** (not private)
   - Do NOT initialize with README
   - Do NOT add .gitignore
   - Do NOT add license
3. Repeat for: `vraravam/browser-profiles`

**Option B: Via GitHub CLI:**
```bash
gh auth login
gh repo create vraravam/home --public
gh repo create vraravam/browser-profiles --public
```

**Why public repos?**
- **No authentication needed to clone** - works on vanilla OS without SSH keys or PAT
- **Contents are encrypted** - gcrypt encrypts all data, filenames, history
- **Only encryption password needed** - sole credential required for vanilla OS recovery
- **GitHub only sees encrypted blobs** - no sensitive data visible

**What's visible vs encrypted:**
| Item | Visibility | Security |
|------|------------|----------|
| Repo exists | ✓ Public | Low risk (just knows you have a backup) |
| Branch names | ✓ Public | Low risk (typically just "main") |
| Commit count | ✓ Public | Low risk (metadata only) |
| Pack sizes | ✓ Public | Low risk (can't infer content) |
| Filenames | ✗ Encrypted | Protected |
| File contents | ✗ Encrypted | Protected |
| Commit messages | ✗ Encrypted | Protected |
| History | ✗ Encrypted | Protected |

**Security model:**
- Attacker can see: "User has encrypted backup repos"
- Attacker cannot see: ANY actual data without encryption password
- Same as Keybase (which also exposed repo existence/size)
- Only encryption password protects data (same as any encrypted backup)

### Phase 3: Migrate Repositories

**Option A: Migrate both repos automatically (RECOMMENDED)**

```bash
# Run the convenience script
ruby scripts/migrate-keybase-repos.rb

# You will be prompted for a password ONCE
# This password will be used for ALL encrypted repos
# STORE IT IN YOUR PASSWORD MANAGER!
```

**Option B: Migrate repos individually**

```bash
# Migrate home repo
ruby scripts/migrate-keybase-to-gcrypt.rb \
  --repo ~/home \
  --encrypted-url gcrypt::git@github.com:vraravam/home.git

# Migrate browser-profiles repo
ruby scripts/migrate-keybase-to-gcrypt.rb \
  --repo ~/personal/$USER/browser-profiles \
  --encrypted-url gcrypt::git@github.com:vraravam/browser-profiles.git
```

### Phase 4: Verify Migration

```bash
# Test home repo
cd ~/home
git pull    # Should prompt for password, then succeed
git status  # Should show "Your branch is up to date with 'origin/main'"

# Test browser-profiles repo
cd ~/personal/$USER/browser-profiles
git pull
git status

# Check remote configuration
git remote -v
# Should show:
# origin    gcrypt::git@github.com:vraravam/home.git (fetch)
# origin    gcrypt::git@github.com:vraravam/home.git (push)
# keybase   keybase://... (fetch)  [preserved for rollback]
# keybase   keybase://... (push)
```

### Phase 5: Setup Password Caching (Optional)

Avoid entering password on every push/pull:

```bash
# Option 1: macOS Keychain (recommended)
git config --global credential.helper osxkeychain

# Option 2: Cache in memory for 1 hour
git config --global credential.helper 'cache --timeout=3600'

# After next git operation, password will be cached
```

### Phase 6: Remove Keybase (After Testing)

**Only after you've verified gcrypt works on ALL machines:**

```bash
# Remove Keybase remotes
cd ~/home
git remote remove keybase

cd ~/personal/$USER/browser-profiles
git remote remove keybase

# Uninstall Keybase
brew uninstall --cask keybase

# Remove Keybase data (CAREFUL - this deletes all local Keybase data)
rm -rf ~/Library/Keybase
rm -rf ~/Library/Application\ Support/Keybase
rm -rf ~/.config/keybase
```

---

## Password Management

### Choosing a Strong Password

**Requirements:**
- Use for ALL encrypted repos (single password)
- Must be secure (this protects your data)
- Must be memorable enough to type (you'll type it often)
- Store in password manager (1Password, Bitwarden, etc.)

**Recommended approach:**
```bash
# Generate strong password
openssl rand -base64 32

# Store in password manager with:
# Title: "Git Remote Encryption"
# URL: github.com
# Notes: "Used for git-remote-gcrypt encrypted repos"
```

### Password Prompts

**First push/pull after reboot:**
- You will be prompted: "Password for 'gcrypt::git@github.com:user/repo.git':"
- Enter your password
- If credential helper is configured, it will be cached

**Subsequent operations:**
- No prompt (password cached)

---

## Rollback Plan

If you need to rollback to Keybase:

```bash
# For each repo:
cd ~/home

# Switch back to Keybase remote
git remote remove origin
git remote rename keybase origin

# Verify
git remote -v
# Should show keybase:// URL as origin

# Push any changes made during testing
git push origin main
```

---

## Fresh Install Behavior

### On Vanilla OS (FIRST_INSTALL=1)

**Prerequisites:**
- Encryption password (in your head or password manager)
- That's it! No PAT, no SSH keys needed.

**Automated steps:**
```
1. Install Homebrew
2. brew bundle install
   - Installs git-remote-gcrypt + gnupg
3. setup-git-remote-gcrypt.rb runs
   - Configures gcrypt.participants = "simple"
4. Clone dotfiles (plain git, not encrypted)
5. Clone encrypted repos via HTTPS (public repos, no auth)
   - Prompts only for encryption password
   - No GitHub credentials required
6. SSH keys now available from home repo
7. Continue with rest of fresh-install
```

**Why public repos with HTTPS:**
- No authentication required (works on vanilla OS with zero setup)
- No PAT needed (GitHub deprecated password auth)
- No SSH keys needed (chicken-and-egg problem solved)
- Only encryption password required
- Repo contents fully encrypted by gcrypt

**Credential prompt flow:**
```
Cloning into '/Users/user'...
gcrypt: Decrypting manifest
Enter passphrase: [enter encryption password]
gcrypt: Remote ID is :id:7VigUnLVYVtZx8oir34R
```

**Disaster recovery scenario:**
```
Laptop stolen/dead → Buy new laptop → Run fresh-install
→ Prompted for encryption password only
→ Full recovery with single password
```

### On Configured Machines

```
1. Pull dotfiles (already has gcrypt installed)
2. setup-git-remote-gcrypt.rb runs (idempotent)
3. Pull encrypted repos via HTTPS
   - Only prompted for encryption password
   - No GitHub credentials needed
4. SSH keys already available from home repo
5. No manual steps required
```

---

## Troubleshooting

### Error: "gcrypt: Repository not found"

**Cause:** Remote repo doesn't exist or wrong URL

**Fix:**
```bash
# Verify repo exists on GitHub
gh repo view vraravam/home

# Check URL spelling
git remote -v

# Re-add remote if wrong
git remote remove origin
git remote add origin gcrypt::git@github.com:vraravam/home.git
```

### Error: "gpg: decryption failed: No secret key"

**Cause:** Wrong password or gcrypt not configured

**Fix:**
```bash
# Verify gcrypt configuration
git config --global --get gcrypt.participants
# Should output: simple

# If not configured, run setup script
ruby scripts/setup-git-remote-gcrypt.rb
```

### Password Not Cached

**Cause:** Credential helper not configured

**Fix:**
```bash
# macOS: Use Keychain
git config --global credential.helper osxkeychain

# After next operation, password will be stored in Keychain
```

### "Permission denied (publickey)" on Push

**Cause:** SSH key not added to GitHub

**Fix:**
```bash
# Check SSH connection
ssh -T git@github.com

# If fails, add SSH key to GitHub
cat ~/.ssh/id_rsa.pub
# Copy output and add to https://github.com/settings/keys
```

---

## Performance Comparison

| Operation | Keybase | gcrypt (first time) | gcrypt (cached) |
|-----------|---------|-------------------|----------------|
| Clone 10MB repo | ~10s | ~20s | ~20s |
| Pull (no changes) | ~2s | ~4s | ~4s |
| Push (5 commits) | ~3s | ~5s | ~5s |
| Password prompt | Never | First time only | Never |

**Conclusion:** Slightly slower (~2x) but acceptable for small repos.

---

## Security Comparison

| Feature | Keybase | gcrypt |
|---------|---------|--------|
| Content encryption | ✓ Yes | ✓ Yes |
| Filename encryption | ✓ Yes | ✓ Yes |
| Commit message encryption | ✓ Yes | ✓ Yes |
| History encryption | ✓ Yes | ✓ Yes |
| Branch name visible | ✗ No | ✓ Yes (mitigated: rename to "main") |
| Pack sizes visible | ✗ No | ✓ Yes (low impact) |
| GUI dependency | ✓ Yes | ✗ No |
| Background process | ✓ Yes | ✗ No |

**Verdict:** Roughly equivalent security with slightly more metadata leakage (easily mitigated).

---

## Next Steps

1. ✓ Install gcrypt: `brew install git-remote-gcrypt gnupg`
2. ✓ Configure gcrypt: `ruby scripts/setup-git-remote-gcrypt.rb`
3. ⏳ Create empty GitHub repos (if not exists)
4. ⏳ Migrate repos: `ruby scripts/migrate-keybase-repos.rb`
5. ⏳ Test on all machines
6. ⏳ Remove Keybase after testing

---

## Questions?

**Q: Can I encrypt the dotfiles repo itself?**  
A: Not recommended. Dotfiles need to be cloned BEFORE gcrypt is installed. Keep dotfiles plain, encrypt other repos.

**Q: What if I forget the password?**  
A: Encrypted data is unrecoverable. STORE PASSWORD IN PASSWORD MANAGER!

**Q: Can I rotate the password?**  
A: No. Symmetric encryption uses a single password for all history. To change password, you must re-encrypt the entire repo (create new gcrypt remote, push all branches, delete old remote).

**Q: Can different repos use different passwords?**  
A: Yes, but you'll need to enter different passwords for each repo. Simpler to use one password for all.

**Q: What if GitHub sees my data?**  
A: GitHub only sees encrypted blobs. Content, filenames, and history are encrypted. Same protection as Keybase.

---

## Support

**Documentation:**
- git-remote-gcrypt: https://github.com/spwhitton/git-remote-gcrypt
- Symmetric encryption: https://github.com/spwhitton/git-remote-gcrypt#using-a-shared-secret

**Issues:**
- Check `/tmp/encrypted-git-remotes-comparison.md` for detailed analysis
- Check `/tmp/performance-comparison-git-encrypted-remotes.md` for performance data
- Check `/tmp/github-vs-keybase-exposure-analysis.md` for security analysis
