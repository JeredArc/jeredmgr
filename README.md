# JeredMgr

JeredMgr is a tool that helps you install, run, and update multiple projects using Docker containers, systemd services, or custom scripts.


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
git clone https://github.com/JeredArc/jeredmgr.git && chmod +x jeredmgr.sh
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
```


## Configuration

Projects are simply and solely stored using an `.env` file for each project in the `projects` sub-directory, where the filename specifies the project name. The following variables are available:

- `ENABLED`: Project enabled status (`true`/`false`)
- `REPO_URL`: GitHub repository URL (must start with `https://github.com/` to work with PAT authentication)
- `PATH`: Local project path
- `USE_GLOBAL_PAT`: Whether to use JeredMgr's global GitHub PAT (`true`/`false`)
- `LOCAL_PAT`: Project-specific GitHub PAT (if `USE_GLOBAL_PAT = false`, leave empty for no or git-configured authentication)
- `TYPE`: Project type (`docker`/`service`/`scripts`)

In the `projects` directory, there are additionally stored:
- an obligatory `<project-name>.docker-compose.yml` file or link for enabled type `docker` projects, which will be used for all `docker compose` commands
- an obligatory `<project-name>.service` file or link for enabled type `service` projects, to which a link in `/etc/systemd/system/` will point to

The global GitHub PAT is stored in `global-pat.txt` and can be modified there.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.


## License

This project is licensed under the GNU General Public License v3.0 (GPL-3.0). See the [LICENSE](LICENSE) file for details.