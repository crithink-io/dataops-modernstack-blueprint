#!/usr/bin/env python3
"""Initialize a new project from the dbt-workflow template.

Usage:
    python scripts/init_project.py

Prompts for project name, author, database names, warehouse name,
and replaces all template values across the codebase.

Requirements: Python 3.8+ (stdlib only, no extra dependencies).
"""

import os
import shutil
import subprocess
import sys

# ── Configuration ────────────────────────────────────────────────────────────

SKIP_DIRS = {".git", "venv", "__pycache__", "target", "dbt_packages", "logs", ".sqlfluff_cache"}
BINARY_EXTENSIONS = {".csv", ".pptx", ".xlsx", ".png", ".jpg", ".gif", ".ico", ".woff", ".woff2", ".pyc"}

PROMPTS = [
    ("project_name",   "Project name (dbt_project.yml)",  "ci_cd_project"),
    ("author_name",    "Author name",                     "Anouar Zbaida"),
    ("organization",   "Organization",                    "Crithink"),
    ("app_database",   "Application database",            "APP_DB"),
    ("ci_database",    "CI/utilities database",           "_DB_UTILS"),
    ("warehouse_name", "Warehouse name",                  "ANALYTICS_WH"),
]


# ── Helpers ──────────────────────────────────────────────────────────────────

def get_project_root():
    """Return the project root (parent of scripts/)."""
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def prompt_values():
    """Prompt user for each configurable value. Returns dict of {key: new_value}."""
    print()
    print("  dbt-workflow Project Initializer")
    print("  =================================")
    print()
    print("  Customize this template for your project.")
    print("  Press Enter to keep the default value shown in [brackets].")
    print()

    values = {}
    for key, label, default in PROMPTS:
        user_input = input(f"  {label} [{default}]: ").strip()
        values[key] = user_input if user_input else default

    return values


def collect_text_files(root):
    """Walk the project and return all text file paths (skipping binary/ignored dirs)."""
    text_files = []
    for dirpath, dirnames, filenames in os.walk(root):
        # Skip ignored directories (modify dirnames in-place to prevent descent)
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]

        for filename in filenames:
            _, ext = os.path.splitext(filename)
            if ext.lower() in BINARY_EXTENSIONS:
                continue
            filepath = os.path.join(dirpath, filename)
            text_files.append(filepath)

    return text_files


def count_replacements(files, old, new):
    """Count how many times old appears across all files (content only)."""
    if old == new:
        return 0, 0
    total_count = 0
    file_count = 0
    for filepath in files:
        try:
            with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
            count = content.count(old)
            if count > 0:
                total_count += count
                file_count += 1
        except (OSError, UnicodeDecodeError):
            continue
    return total_count, file_count


def replace_in_files(files, old, new):
    """Replace all occurrences of old with new in file contents."""
    if old == new:
        return 0
    total = 0
    for filepath in files:
        try:
            with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
            count = content.count(old)
            if count > 0:
                new_content = content.replace(old, new)
                with open(filepath, "w", encoding="utf-8") as f:
                    f.write(new_content)
                total += count
        except (OSError, UnicodeDecodeError):
            continue
    return total


def rename_path(root, old_name, new_name):
    """Rename a file or directory under root. Returns True if renamed."""
    if old_name == new_name:
        return False

    old_path = os.path.join(root, old_name)
    new_path = os.path.join(root, new_name)

    if os.path.exists(old_path):
        # Ensure parent of new_path exists
        os.makedirs(os.path.dirname(new_path), exist_ok=True)
        shutil.move(old_path, new_path)
        return True
    return False


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    root = get_project_root()
    values = prompt_values()

    # Build replacement pairs: (old, new, label)
    replacements = [
        (PROMPTS[0][2], values["project_name"],   "project name"),
        (PROMPTS[1][2], values["author_name"],     "author name"),
        (PROMPTS[2][2], values["organization"],    "organization"),
        (PROMPTS[3][2], values["app_database"],    "application database"),
        (PROMPTS[4][2], values["ci_database"],     "CI/utilities database"),
        (PROMPTS[5][2], values["warehouse_name"],  "warehouse name"),
    ]

    # Directory/file renames to perform
    dir_renames = [
        (os.path.join("ddls", PROMPTS[3][2]),
         os.path.join("ddls", values["app_database"])),
        (os.path.join("ddls", PROMPTS[4][2]),
         os.path.join("ddls", values["ci_database"])),
    ]
    file_renames = [
        (os.path.join("ddls", "_account", "databases", f"{PROMPTS[3][2]}.sql"),
         os.path.join("ddls", "_account", "databases", f"{values['app_database']}.sql")),
        (os.path.join("ddls", "_account", "databases", f"{PROMPTS[4][2]}.sql"),
         os.path.join("ddls", "_account", "databases", f"{values['ci_database']}.sql")),
        (os.path.join("ddls", "_account", "warehouses", f"{PROMPTS[5][2]}.sql"),
         os.path.join("ddls", "_account", "warehouses", f"{values['warehouse_name']}.sql")),
    ]

    # Filter out no-ops
    replacements = [(old, new, label) for old, new, label in replacements if old != new]
    dir_renames = [(old, new) for old, new in dir_renames if old != new]
    file_renames = [(old, new) for old, new in file_renames if old != new]

    if not replacements and not dir_renames and not file_renames:
        print("\n  All values match defaults. Nothing to change.")
        return

    # Collect text files for scanning
    text_files = collect_text_files(root)

    # ── Dry-run summary ──────────────────────────────────────────────────

    print()
    print("  Changes to apply:")

    for old, new, label in replacements:
        total, files = count_replacements(text_files, old, new)
        if total > 0:
            print(f"    - Replace '{old}' -> '{new}' ({total} occurrences in {files} files)")
        else:
            print(f"    - Replace '{old}' -> '{new}' (0 occurrences found)")

    for old, new in dir_renames:
        old_path = os.path.join(root, old)
        if os.path.exists(old_path):
            print(f"    - Rename directory: {old} -> {new}")

    for old, new in file_renames:
        old_path = os.path.join(root, old)
        if os.path.exists(old_path):
            print(f"    - Rename file: {old} -> {os.path.basename(new)}")

    print()
    confirm = input("  Apply these changes? [Y/n]: ").strip().lower()
    if confirm and confirm != "y":
        print("  Aborted.")
        return

    # ── Apply changes ────────────────────────────────────────────────────

    # 1. Rename directories first (before file content replacement)
    for old, new in dir_renames:
        if rename_path(root, old, new):
            print(f"  Renamed: {old} -> {new}")

    # 2. Rename individual files
    for old, new in file_renames:
        if rename_path(root, old, new):
            print(f"  Renamed: {old} -> {os.path.basename(new)}")

    # 3. Re-collect text files after renames
    text_files = collect_text_files(root)

    # 4. Replace file contents
    total_replacements = 0
    for old, new, label in replacements:
        count = replace_in_files(text_files, old, new)
        total_replacements += count

    print()
    print(f"  Done! {total_replacements} replacements applied.")

    # ── Git remote & initial commit ───────────────────────────────────────

    git_dir = os.path.join(root, ".git")
    if os.path.isdir(git_dir):
        print()
        print("  ── Git Setup ──")
        print()
        repo_url = input("  New Git repository URL (leave blank to skip): ").strip()

        if repo_url:
            # Update remote origin
            try:
                subprocess.run(
                    ["git", "remote", "set-url", "origin", repo_url],
                    cwd=root, check=True, capture_output=True, text=True,
                )
                print(f"  Remote origin updated to: {repo_url}")
            except subprocess.CalledProcessError:
                # origin might not exist (e.g. fresh git init), add it
                subprocess.run(
                    ["git", "remote", "add", "origin", repo_url],
                    cwd=root, check=True, capture_output=True, text=True,
                )
                print(f"  Remote origin set to: {repo_url}")

            # Detect current branch
            result = subprocess.run(
                ["git", "branch", "--show-current"],
                cwd=root, capture_output=True, text=True,
            )
            branch = result.stdout.strip() or "main"

            # Offer initial commit + push
            print()
            push_confirm = input(
                f"  Create initial commit and push to '{branch}'? [Y/n]: "
            ).strip().lower()

            if not push_confirm or push_confirm == "y":
                subprocess.run(["git", "add", "-A"], cwd=root, check=True)
                subprocess.run(
                    ["git", "commit", "-m", "Initialize project from dbt-workflow template"],
                    cwd=root, check=True,
                )
                print(f"  Initial commit created.")

                try:
                    subprocess.run(
                        ["git", "push", "-u", "origin", branch],
                        cwd=root, check=True,
                    )
                    print(f"  Pushed to origin/{branch}.")
                except subprocess.CalledProcessError as e:
                    print(f"  Push failed (is the remote repo created?). You can push manually:")
                    print(f"    git push -u origin {branch}")
            else:
                print("  Skipped. You can commit and push manually later.")
        else:
            print("  Skipped Git setup. Remote origin unchanged.")
            print("  To update later: git remote set-url origin <your-repo-url>")
    else:
        print()
        print("  No .git directory found. To set up Git:")
        print("    git init && git remote add origin <your-repo-url>")
        print("    git add -A && git commit -m 'Initial commit' && git push -u origin main")

    # ── Optionally delete this script ────────────────────────────────────

    print()
    delete = input("  Delete this init script? [y/N]: ").strip().lower()
    if delete == "y":
        script_path = os.path.abspath(__file__)
        os.remove(script_path)
        # Remove scripts/ dir if empty
        scripts_dir = os.path.dirname(script_path)
        if os.path.isdir(scripts_dir) and not os.listdir(scripts_dir):
            os.rmdir(scripts_dir)
        print("  Init script deleted.")
    else:
        print("  Init script kept. You can re-run it or delete it manually.")

    print()


if __name__ == "__main__":
    main()
