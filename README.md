# JeredMgr

JeredMgr is a tool that helps you install, run, and update multiple projects using Docker containers, systemd services, or custom scripts.


## Changes in 1.1.1

- Several projects can be given as one comma-separated argument without spaces, e.g. `jm restart foo,bar` or `jm start foo,audio-+,.`. Each entry can be a name, a `+` wildcard or `.`. Only wildcards matching several projects ask for confirmation, explicit names are used as given.
- `remove` accepts several projects (comma-separated full names, still no wildcard and no `.`).
- `logs` only follows when a single project is selected, with several projects (also via wildcard) it shows the last lines of each.
- `update` no longer tries to pull images of services with a `build` section (they only exist locally and failed the update). These are rebuilt on install after a git update instead.
- Running JeredMgr without arguments additionally shows the current global config (`HOME_DIR`, including how it was determined, `DATA_DIR`, `LOGS_DIR`).
- Paths in the output are abbreviated with `~` based on the same home directory that `~` is expanded to (see `HOME_DIR`), instead of `$HOME`.


## ⚠️ Breaking changes in 1.1.0

- **Full git repo directory renamed:** Projects using `SUBDIR` now keep their full clone in `projects/<project-name>.fullgitrepo` instead of `projects/<project-name>-fullgitrepo`. Existing directories are renamed automatically (and the project path link is re-pointed) the next time JeredMgr loads such a project.
- **Docker compose project directory is the real path:** `--project-directory` is now passed with symlinks resolved. For `SUBDIR` projects, relative paths in the compose file (e.g. `../shared.conf`) now resolve inside the repository instead of JeredMgr's projects directory.
  The **compose project name** is affected as follows:
  - `SUBDIR` projects: JeredMgr now passes `-p <project-name>` unless the compose file sets a top-level `name:`. Previously, the name was derived from the basename of `PATH` (the link). So only `SUBDIR` projects whose `PATH` basename differs from the project name get a new compose project name.
  - Projects without `SUBDIR` whose `PATH` is a symlink: the name is now derived from the link target's directory name instead of the link's name.
  - Projects without `SUBDIR` whose `PATH` is a real directory are not affected.

  **Stop affected docker projects before upgrading**, otherwise JeredMgr won't find their containers anymore (fix afterwards with `docker compose -p <old-name> down`). Also note that named volumes are prefixed with the compose project name, so affected projects would start with new, empty named volumes (the old ones remain under the old name).
- **`~` is no longer `$HOME`:** A leading `~` in a project's `PATH` (and in the new global settings) now means the first parent of JeredMgr's directory that is a user's home directory, or `HOME_DIR` from `global-config.env`. This only differs from before when JeredMgr runs as a different user (e.g. with `sudo`).
- **`path` command returns the real path for `SUBDIR` projects** (the sub directory inside the full git repo) instead of the link.

Non-breaking changes in 1.1.0:
- `update` only installs and restarts `SUBDIR` projects if something in the sub directory or in the project's `WATCH_PATHS` changed (new docker images still trigger a restart).
- New optional `global-config.env` with `HOME_DIR`, `DATA_DIR`, `LOGS_DIR` (see [Configuration](#configuration)).
- New `dc` command: `jm dc <project> <args>` runs `docker compose` with arbitrary arguments and the same parameters JeredMgr uses (compose file, project directory, project name, `JEREDMGR_*` variables).
- New project names may contain dashes, but must start with a lowercase letter (so they are always valid docker compose project names). Existing projects are not checked.


## Features

- **Multiple Project Types Support**:
  - Docker containers (docker compose)
  - Systemd services
  - Custom scripts
- **Project Management**:
  - Easy adding/creating of new projects
  - Start/stop/restart functionality
  - Status monitoring
  - Log viewing
  - Automatic updates
- **GitHub Integration**:
  - Automatic repository cloning upon adding
  - Global and per-project PAT (Personal Access Token) support
  - Update tracking
- **Docker Support**:
  - Automatic compose file generation
  - User-aided basic Dockerfile generation
  - Container status monitoring
  - Image updates and removal of obsolete images
- **Systemd Integration**:
  - User-aided basic service file generation
  - Automatic service linking
  - Status monitoring via systemctl


## Installation

```bash
git clone https://github.com/JeredArc/jeredmgr.git && chmod +x jeredmgr/jeredmgr.sh
```
It's as simple as that!


## Basic Usage (run help for full list)

```bash
# Show help
./jeredmgr.sh help

# Add a new project
./jeredmgr.sh add

# List all projects
./jeredmgr.sh list

# Enable and install or re-install a project
./jeredmgr.sh enable <project>

# Start a project
./jeredmgr.sh start <project>

# Show project status
./jeredmgr.sh status <project>

# View project logs
./jeredmgr.sh logs <project>

# Update a project
./jeredmgr.sh update <project>

# Select several projects: comma-separated, '+' as wildcard, '.' for the project of the current directory
./jeredmgr.sh restart foo,bar
./jeredmgr.sh update audio-+
./jeredmgr.sh status .

# Run any docker compose command in a docker project's context
./jeredmgr.sh dc <project> ps
./jeredmgr.sh dc <project> exec <service> sh
```


## Configuration

Projects are simply and solely stored using an `.env` file for each project in the `projects` sub-directory, where the filename specifies the project name. The following variables are available:

- `ENABLED`: Project enabled status (`true`/`false`)
- `REPO_URL`: GitHub repository URL (must start with `https://github.com/` to work with PAT authentication)
- `SUBDIR`: Optional sub directory inside the repository to use as project (the full repo is cloned to `projects/<project-name>.fullgitrepo` and `PATH` becomes a link to the sub directory)
- `WATCH_PATHS`: Optional space-separated paths inside the repository (relative to its root) that, besides `SUBDIR`, require install and restart on `update` when changed (e.g. shared config files)
- `PATH`: Local project path (a leading `~` is expanded, see `HOME_DIR` below)
- `USE_GLOBAL_PAT`: Whether to use JeredMgr's global GitHub PAT (`true`/`false`)
- `LOCAL_PAT`: Project-specific GitHub PAT (if `USE_GLOBAL_PAT = false`, leave empty for no or git-configured authentication)
- `TYPE`: Project type (`docker`/`service`/`scripts`)

In the `projects` directory, there are additionally stored:
- an obligatory `<project-name>.docker-compose.yml` file or link for enabled type `docker` projects, which will be used for all `docker compose` commands
- an obligatory `<project-name>.service` file or link for enabled type `service` projects, to which a link in `/etc/systemd/system/` will point to
- a `<project-name>.fullgitrepo` directory with the full repository clone for projects using `SUBDIR`

The global GitHub PAT is stored in `global-pat.txt` and can be modified there.

Optional global settings can be stored in `global-config.env` in JeredMgr's directory:
- `HOME_DIR`: Absolute directory used to expand a leading `~` (default: the first parent of JeredMgr's directory that is a user's home directory; only needed if JeredMgr is located outside of any home directory and `~` is used)
- `DATA_DIR`: Base directory for project data, e.g. `~/data`
- `LOGS_DIR`: Base directory for project logs, e.g. `~/logs`

Relative `DATA_DIR` / `LOGS_DIR` values are relative to JeredMgr's directory. For each project, JeredMgr exports `JEREDMGR_DATA_DIR` / `JEREDMGR_LOGS_DIR` (base directory + `/<project-name>`) to all `docker compose` calls and scripts, and creates these directories on install, start and restart. Compose files can use them with a fallback for running without JeredMgr, e.g.:

```yaml
volumes:
  - ${JEREDMGR_DATA_DIR:-./data}:/data
  - ${JEREDMGR_LOGS_DIR:-./logs}:/logs
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.


## License

This project is licensed under the GNU General Public License v3.0 (GPL-3.0). See the [LICENSE](LICENSE) file for details.