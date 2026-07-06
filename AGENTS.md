# Agent Instructions

Instructions for AI agents working on this repository.

## Project Overview

Thin bash wrapper around [zfs-autobackup](https://github.com/psy0rz/zfs_autobackup).
Main script: `zfs-autobackup-wrapper.sh` (deployed on hosts as `/root/scripts/backup_zfs.sh`
with a site-specific `backup_zfs.conf` next to it). Canonical remote is Gitea
(`gitea.marvin.ar`); GitHub is a push mirror — merge PRs on Gitea only.

## Publishing Release Announcements (Social Media)

When a new version is released (or the user asks to "publish" / "announce" a version),
generate **three** announcement files in the `social/` directory, one per channel.
Use the existing files in `social/` as style references — match their structure,
tone and emoji usage. All content in **English**.

### 1. `social/RELEASE_v<version>.md` — Release notes

Long-form markdown used as the release body on Gitea/GitHub. Follow the structure of
`social/RELEASE_v1.1.0.md`:

- Title: `# <emoji> v<version>: <short tagline>`
- One-paragraph summary of why the release exists (lead with the user-facing problem it solves)
- `## ✨ What's New` — grouped feature sections with bold leads
- A "Before vs After" comparison when the release changes behavior
- `## 💡 What This Version Does` — ✅ Included / ❌ Still Intentionally Simple lists
- `## 🐛 Bug Fixes` — if applicable
- `## 📚 Why This Matters` — closing rationale

Source material: the `Changelog` block in the script header, `README.md`, and the
commit messages since the previous version tag.

### 2. `social/LINKEDIN_v<version>.md` — LinkedIn post

Follow `social/LINKEDIN_v1.1.0.md`:

- Opening line: `🚀 ZFS Autobackup Wrapper v<version> 🚀`
- Sections with emoji bullets: `✨ Key Features` (evergreen project features),
  `🔧 Improvements in this version`, `🛠️ Technical Highlights`, `📚 Documentation`,
  `🔗 Useful Links`
- Blank line between every bullet (LinkedIn formatting)
- Links: GitHub repo URL in full; external links may use `lnkd.in` short forms
- Close with hashtags: `#ZFS #Backup #Linux #OpenZFS #SysAdmin #DataProtection #Automation`
  plus 1-2 release-specific tags

### 3. `social/X_v<version>.md` — X/Twitter post

Follow `social/X_v1.1.0.md`: compact, ~350 characters max.

- Line 1: `⚡ #ZFS backup wrapper v<version> - <hook>!`
- `✨ Features:` + 3-4 one-line emoji bullets (the most attention-grabbing changes only)
- One hashtag line: `#Linux #Storage #Backup #SysAdmin #OpenZFS`
- Last line: repo URL

### Process

1. Read the script header changelog and `git log` since the last version to collect changes.
2. Write the three files. Do NOT overwrite files of previous versions.
3. Commit them with message `social: add v<version> announcements` and push.
4. Publishing to the networks themselves is manual: the user copies the content.
   Do not attempt to post to any social network directly.
