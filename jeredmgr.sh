#!/bin/bash

####################################################################
# JeredMgr 1.0.39                                                  #
# A tool that helps you install, run, and update multiple projects #
# using Docker containers, systemd services, or custom scripts.    #
####################################################################

# Configuration
PROJECTS_DIR="./projects"           # projects directory, folder where all .env files live
SELFUPDATE_REPO_URL="https://github.com/JeredArc/jeredmgr.git"   # JeredMgr repository URL
GLOBAL_PAT_FILE="./global-pat.txt"  # file where the global GitHub PAT is stored
LOG_LINES=10                        # how many log lines to show with log by default when showing logs for all projects
DEFAULT_DOCKER_IMAGE="node:22-alpine3.20"
STATUS_CHECK_RETRIES=10             # how many times to retry checking status (100ms wait) after starting or stopping a project
VERSION=$(grep -E "^# JeredMgr [0-9]+\.[0-9]+\.[0-9]+" $0 | sed -E 's/^# JeredMgr ([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
SCRIPT_NAME=$(basename "$0")

# Shell formatting
if [ -t 1 ]; then  # Only use colors when outputting to terminal
	ESC=$(echo -ne "\033")
	BOLD="${ESC}[1m"
	DIM="${ESC}[2m"
	ITALIC="${ESC}[3m"
	UNDERLINE="${ESC}[4m"
	RED="${ESC}[31m"
	GREEN="${ESC}[32m"
	YELLOW="${ESC}[33m"
	BLUE="${ESC}[34m"
	MAGENTA="${ESC}[35m"
	CYAN="${ESC}[36m"
	RESET="${ESC}[0m"
	DARKGRAY="${ESC}[90m"
else  # No colors when piping
	BOLD=""
	DIM=""
	ITALIC=""
	UNDERLINE=""
	RED=""
	GREEN=""
	YELLOW=""
	BLUE=""
	MAGENTA=""
	CYAN=""
	RESET=""
	DARKGRAY=""
fi

# Utility: Format section headers
format_header() {  # args: $text, reads: none, sets: none
	echo -e "${BOLD}${BLUE}${1//${RESET}/${RESET}${BOLD}${BLUE}}${RESET}"
}

# Utility: Format command names
format_command() {  # args: $command, reads: none, sets: none
	echo -e "${BOLD}${CYAN}${1//${RESET}/${RESET}${BOLD}${CYAN}}${RESET}"
}

# Utility: Format project names
format_project() {  # args: $project, reads: none, sets: none
	echo -e "${BOLD}${MAGENTA}${1//${RESET}/${RESET}${BOLD}${MAGENTA}}${RESET}"
}

# Utility: Format paths
format_path() {  # args: $path, reads: none, sets: none
	local path="$1"
	path="${path/#$HOME/\~}"  # Replace home directory with ~
	echo -e "${UNDERLINE}${DARKGRAY}${path//${RESET}/${RESET}${UNDERLINE}${DARKGRAY}}${RESET}"
}

# Utility: Format success messages
format_success() {  # args: $message, reads: none, sets: none
	echo -e "${GREEN}Success:${RESET} $1"
}

# Utility: Format error messages
format_error() {  # args: $message, reads: none, sets: none
	echo -e "${RED}Error:${RESET} $1" 1>&2
}

# Utility: Format warning messages
format_warning() {  # args: $message, reads: none, sets: none
	echo -e "${YELLOW}Warning:${RESET} $1"
}

# Utility: Format status indicators
format_status() {  # args: $status, reads: none, sets: none
	case "$1" in
		"✓"|"Yes") echo -e "${GREEN}$1${RESET}" ;;
		"✗"|"No") echo -e "${RED}$1${RESET}" ;;
		"⏹") echo -e "${RED}$1${RESET}" ;;
		"?") echo -e "${YELLOW}$1${RESET}" ;;
		*) echo -e "${YELLOW}$1${RESET}" ;;
	esac
}

# Utility: List available commands and their descriptions.
list_commands() {  # args: none, reads: none, sets: none
	echo -e "Usage: ${BOLD}$SCRIPT_NAME${RESET} $(format_command "<command>") $(format_project "[project]") ${BOLD}[options]${RESET}"
	echo -e ""
	format_header "# Available commands:"
	echo -e "   $(format_command "help")                Show help"
	echo -e "   $(format_command "add")                 Add a new (for now disabled) project (create its .env file)"
	echo -e "   $(format_command "remove")              Remove a project (check for it being disabled, then delete its .env file)"
	echo -e "   $(format_command "list")                List all projects"
	echo -e "   $(format_command "enable") $(format_project "[project]")    Install and enable project(s), run again to re-install"
	echo -e "   $(format_command "disable") $(format_project "[project]")   Disable and uninstall project(s)"
	echo -e "   $(format_command "start") $(format_project "[project]")     Start enabled project(s)"
	echo -e "   $(format_command "stop") $(format_project "[project]")      Stop project(s)"
	echo -e "   $(format_command "restart") $(format_project "[project]")   Restart enabled project(s)"
	echo -e "   $(format_command "status") $(format_project "[project]")    Show status (enabled + running) and extended status with explicit project name"
	echo -e "   $(format_command "logs") $(format_project "<project>")      Show logs for one project"
	echo -e "   $(format_command "shell") $(format_project "<project>")     Open a shell in the project container"
	echo -e "   $(format_command "update") $(format_project "[project]")    Update project(s) using git, with no project specified, self-update is run at first"
	echo -e "   $(format_command "self-update")         Update manager script"
	echo -e ""
	format_header "# Options and parameters:"
	echo -e "   ${BOLD}-q${RESET}, ${BOLD}--quiet${RESET}                 Suppress prompts (for automation)"
	echo -e "   ${BOLD}-f${RESET}, ${BOLD}--force${RESET}                 Force actions without confirmation prompts (use with caution)"
	echo -e "   ${BOLD}-s${RESET}, ${BOLD}--no-status-check${RESET}       Don't retry checking status after starting or stopping a project"
	echo -e "   ${BOLD}-n${RESET}, ${BOLD}--number-of-lines <N>${RESET}   Show N log lines or use 'f' (follow) for 'logs' command (default: follow / for all projects $LOG_LINES)"
}

# Command: Print detailed help and workflow information for JeredMgr.
show_help() {  # args: none, reads: none, sets: none
	echo -e "Welcome to JeredMgr ${BOLD}${GREEN}$VERSION${RESET}, a tool that helps you install, run, and update multiple projects"
	echo -e "using Docker containers, systemd services, or custom scripts!"
	echo -e ""
	list_commands
	echo -e ""
	format_header "# When installing (enabling or updating) a project, JeredMgr will:"
	echo -e ""
	echo -e "- Look for a $(format_path "setup.sh") script in the project path and run it."
	echo -e ""
	echo -e "- Type '${BOLD}docker${RESET}'"
	echo -e "   Link the $(format_path "<project-name>.docker-compose.yml") file in the projects directory, chosen in the following order:"
	echo -e "   - Already existing regular file $(format_path "<project-name>.docker-compose.yml") in the projects directory"
	echo -e "   - A $(format_path "docker-compose.yml") file in the project path"
	echo -e "   - A $(format_path "docker-compose-default.yml") file in the project path"
	echo -e "   - A valid $(format_path "<project-name>.docker-compose.yml") link file in the projects directory"
	echo -e "   - Look for a $(format_path "Dockerfile") in the project directory and create a $(format_path "<project-name>.docker-compose.yml") file in the projects directory from that"
	echo -e "     with a comment ${ITALIC}${DARKGRAY}'# Auto-generated by JeredMgr, will remove images on uninstall'${RESET}"
	echo -e "   - Otherwise offer to create a $(format_path "Dockerfile") in the project path"
	echo -e ""
	echo -e "- Type '${BOLD}service${RESET}'"
	echo -e "   Link the $(format_path "<project-name>.service") file in the projects directory, chosen in the following order:"
	echo -e "   - Already installed regular file $(format_path "<project-name>.service") in the projects directory"
	echo -e "   - A $(format_path "<project-name>.service") file in the project path"
	echo -e "   - A $(format_path "default.service") file in the project path"
	echo -e "   - A valid $(format_path "<project-name>.service") link file in the projects directory"
	echo -e "   - Otherwise offer to create a $(format_path "<project-name>.service") file in the projects directory"
	echo -e "   - A link to the $(format_path "<project-name>.service") file will be created in $(format_path "/etc/systemd/system/")"
	echo -e ""
	format_header "# When running a project, JeredMgr will:"
	echo -e ""
	echo -e "- Type '${BOLD}docker${RESET}'"
	echo -e "  Run the project with ${BOLD}\`docker compose -f <project-name>.docker-compose.yml --project-directory <project-path> up -d\`${RESET} / ${BOLD}\`... down\`${RESET} etc."
	echo -e "  (Keep in mind: If a docker project is stopped, it does not automatically start again on reboot,"
	echo -e "   as ${BOLD}\`docker compose ... down\`${RESET} removes the container. That way, changes to the compose file automatically take effect.)"
	echo -e ""
	echo -e "- Type '${BOLD}service${RESET}'"
	echo -e "  Run the project with ${BOLD}\`systemctl start <project-name>\`${RESET} / ${BOLD}\`... stop\`${RESET} etc."
	echo -e "  (Keep in mind: If a service project is stopped, it automatically starts again on reboot,"
	echo -e "   as ${BOLD}\`systemctl stop ...\`${RESET} does not disable the service. Changes to the service file will only take effect with calling enable again or on a reboot.)"
	echo -e ""
	echo -e "- Type '${BOLD}scripts${RESET}'"
	echo -e "  Look for the following scripts in the project path and run them with the corresponding commands:"
	echo -e "  - $(format_path "start.sh")"
	echo -e "  - $(format_path "stop.sh")"
	echo -e "  - $(format_path "restart.sh") (otherwise $(format_path "start.sh") + $(format_path "stop.sh"))"
	echo -e "  - $(format_path "status.sh")"
	echo -e "  - $(format_path "logs.sh")"
	echo -e ""
	format_header "# When uninstalling a project, JeredMgr will:"
	echo -e ""
	echo -e "- Stop the project if running"
	echo -e ""
	echo -e "- Type '${BOLD}docker${RESET}'"
	echo -e "   Remove the docker container"
	echo -e "   If the $(format_path "docker-compose.yml") file has the ${ITALIC}${DARKGRAY}'# Auto-generated ...'${RESET} comment, remove all docker images named <project-name>"
	echo -e ""
	echo -e "- Type '${BOLD}service${RESET}'"
	echo -e "   Delete the service file link from $(format_path "/etc/systemd/system/")"
	echo -e "   Remove the service with ${BOLD}\`systemctl daemon-reload\`${RESET}"
	echo -e ""
	echo -e "- Type '${BOLD}scripts${RESET}'"
	echo -e "  Look for a $(format_path "uninstall.sh") script in the project path and run it"
	echo -e ""
	echo -e "- The project with its $(format_path ".env") file isn't deleted, so it can be re-enabled again later"
	echo -e ""
	format_header "# When updating a project, JeredMgr will:"
	echo -e ""
	echo -e "- Look for an $(format_path "update.sh") script in the project path and run it"
	echo -e ""
	echo -e "- Else:"
	echo -e "  - Update the project using git if it's a git repository"
	echo -e "  - Pull new images from the docker repositories if it's a docker project"
	echo -e ""
	format_header "# Further notes:"
	echo -e ""
	echo -e "- The provided project name can contain '${ITALIC}${DARKGRAY}+${RESET}' as wildcard to match a single project"
	echo -e ""
	echo -e "- To select a sub directory from a git repository, provide it when creating the project or set the ${DARKGRAY}SUBDIR${RESET} variable in the $(format_path ".env") file"
	echo -e "  The full repo will then be cloned into a subdirectory of JeredMgr's projects directory,"
	echo -e "  and the project path will be set up as a link pointing to the sub directory."
}

################################################################################
# Utility functions
################################################################################

# Utility: check if git is installed, otherwise exit
ensure_git_installed() {  # args: none, reads: none, sets: none
	if ! command -v git >/dev/null 2>&1; then
		format_error "git is not installed or not in PATH."
		exit 1
	fi
}

# Utility: return whether git is available in supplied path
check_git_path() {  # args: $gitdir, reads: none, sets: none
	local gitdir="$1"
	if ! git -C "$gitdir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		return 1
	fi
}

# Utility: check whether upstream commit equals local commit without fetching (run in subshell, don't use format_ functions here!)
check_git_upstream() {  # args: $path, reads: none, sets: none
	local gitdir="$1"
	local upstream_ref=$(git -C "$gitdir" rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null) || { echo "No upstream configured" 1>&2; return 1; }
	local remote_name=$(echo "$upstream_ref" | cut -d'/' -f1)
	local remote_branch=$(echo "$upstream_ref" | cut -d'/' -f2-)
	local upstream_commit=$(git -C "$gitdir" ls-remote --refs -q "$remote_name" "refs/heads/$remote_branch" 2>/dev/null) || {
		echo "Failed to get upstream commit" 1>&2
		return 1
	}
	upstream_commit=$(echo "$upstream_commit" | awk '{print $1}')
	if [ -z "$upstream_commit" ]; then
		echo "No upstream commit found" 1>&2
		return 1
	fi
	local local_commit=$(git -C "$gitdir" rev-parse HEAD 2>/dev/null)
	if [ "$upstream_commit" = "$local_commit" ]; then
		return 0
	else
		return 2
	fi
}	


# Utility: prompt user for global GitHub PAT and store it in $GLOBAL_PAT_FILE
prompt_global_pat() {  # args: none, reads: none, sets: pat
	if [ ! -f "$GLOBAL_PAT_FILE" ] || [ ! -s "$GLOBAL_PAT_FILE" ]; then
		if $option_quiet; then
			echo "Please run once without -q to provide a global GitHub PAT." 1>&2
			return 1
		else
			read -p "Enter your global GitHub PAT: " pat
			touch "$GLOBAL_PAT_FILE"
			chmod 600 "$GLOBAL_PAT_FILE"
			echo "$pat" > "$GLOBAL_PAT_FILE"
		fi
	else
		# Check file permissions
		local file_perms=$(stat -c "%a" "$GLOBAL_PAT_FILE")
		if [ "$file_perms" != "600" ]; then
			if $option_quiet; then
				echo "Warning: Global PAT file has incorrect permissions ($file_perms instead of 600)!" 1>&2
			else
				if prompt_yes_no "Warning: Global PAT file has incorrect permissions ($file_perms instead of 600). Fix now?"; then
					chmod 600 "$GLOBAL_PAT_FILE"
				fi
			fi
		fi
	fi
	global_pat=$(<"$GLOBAL_PAT_FILE")
}

# Utility: get full repository URL including possible PAT from plain URL without PAT (run in subshell, don't use format_ functions here!)
get_repo_pat_url() {  # args: $repo_url $use_global_pat $local_pat, reads: $global_pat, sets: none
	local repo_url="$1"
	local use_global_pat="$2"
	local local_pat="$3"
	local pat=""

	if ! echo "$repo_url" | grep -q "github.com" && ($use_global_pat || [ -n "$local_pat" ]); then
		echo "Warning: PAT authentication is configured, but the repository is not a GitHub repository (doesn't contain 'github.com' in the URL)." 1>&2
		return 1
	fi

	if $use_global_pat; then
		if ! prompt_global_pat; then return 1; fi
		# Check if global_pat is empty
		if [ -z "$global_pat" ]; then
			echo "Please provide a global GitHub PAT or reconfigure the project to use a different authentication method!" 1>&2
			return 1
		fi
		pat="$global_pat"
	else
		pat="$local_pat"
	fi

	if [ -n "$pat" ]; then
		# Insert PAT into repository URL
		echo "${repo_url/github.com/${pat}@github.com}"
	else
		# No global PAT, local PAT is empty, assume either public repo or git-globally configured authentication
		echo "$repo_url"
	fi  
}


# Utility: read value from .env file (run in subshell, don't use format_ functions here!)
read_env_value() {  # args: $key, reads: env_file, sets: none
	local key="$1"
	grep "^${key}=" "$env_file" | cut -d'#' -f1 | cut -d'=' -f2
}

# Utility: write or update a value in .env file
write_env_value() {  # args: $key $value, reads: $env_file, sets: none
	local key="$1"
	local value="$2"
	
	grep -q "^${key}=" "$env_file" \
		&& sed -i "s|^${key}=.*|${key}=${value}|" "$env_file" \
		|| echo "${key}=${value}" >> "$env_file"
	chmod 600 "$env_file"
}

# Utility: check project type
check_project_type() {  # args: none, reads: $type, sets: $type_checked
	# Check if type is one of the supported values
	type_checked=false  # certain to be boolean
	if [ "$type" = "docker" ] || [ "$type" = "service" ] || [ "$type" = "scripts" ]; then
		type_checked=true
	fi	
}

# Utility: load project values
load_project_values() {  # args: $project_name, reads: none, sets: $project_name $env_file $enabled $repo_url $path $gitpath $use_global_pat $local_pat $type $type_checked
	project_name="$1"
	env_file="$PROJECTS_DIR/$project_name.env"
	if [ ! -f "$env_file" ]; then
		format_error "Project $(format_project "$project_name") not found."
		exit 1
	fi

	enabled=$(read_env_value "ENABLED")
	if ! $enabled; then  # force to boolean
		enabled=false
	fi
	repo_url=$(read_env_value "REPO_URL")
	subdir=$(read_env_value "SUBDIR")
	use_global_pat=$(read_env_value "USE_GLOBAL_PAT")
	if ! $use_global_pat; then  # force to boolean
		use_global_pat=false
	fi
	local_pat=$(read_env_value "LOCAL_PAT")
	path=$(read_env_value "PATH")
	type=$(read_env_value "TYPE")

	# Initialize gitpath based on whether subdir is specified
	if [ -n "$subdir" ]; then
		gitpath="$PROJECTS_DIR/${project_name}-fullgitrepo"
	else
		gitpath="$path"
	fi

	check_project_type

	# Check if docker is installed
	if [ "$type" = "docker" ]; then
		if ! command -v docker >/dev/null 2>&1; then
			format_error "docker is not installed or not in PATH (needed for docker type project $(format_project "$project_name"))."
			return 1
		fi
	fi
}

# Utility: generate compose file content (run in subshell, don't use format_ functions here!)
generate_compose_file_content() {  # args: none, reads: $project_name $path, sets: none
	local dockerfile_contents=$(cat "$path/Dockerfile" 2>/dev/null)

	echo -e "# Auto-generated by JeredMgr, will remove images on uninstall"
	echo -e "services:"
	echo -e "  $project_name:"
	echo -e "    build: $path"
	echo -e "    container_name: $project_name"

	local ports=$(echo "$dockerfile_contents" | grep -E "^EXPOSE" | sed 's/EXPOSE //g' | sed 's/ /:/g' | sed 's/^/      - /g')
	if [ -n "$ports" ]; then
		echo -e "    ports:"
		echo -e "$ports"
	else
		echo -e "#    ports:"
		echo -e "#      - 8700:8700"
	fi

	local envvars=$(echo "$dockerfile_contents" | grep -E "^ENV" | sed 's/ENV //g' | sed 's/ /=/g' | sed 's/^/      - /g')
	if [ -n "$envvars" ]; then
		echo -e "    environment:"
		echo -e "$envvars"
	else
		echo -e "#    environment:"
		echo -e "#      - NODE_ENV=production"
	fi

	echo -e "    restart: always"
}

# Utility: Ensure a canonical symlinked compose file exists for the project, generating or linking as needed.
select_compose_file() {  # args: none, reads: $project_name $path, sets: $compose_file
	compose_file="$PROJECTS_DIR/$project_name.docker-compose.yml"
	# If already a regular file itself (not a symlink), use it
	if [ -f "$compose_file" ] && [ ! -L "$compose_file" ]; then
		echo -e "Using compose file: $(format_path "$compose_file")"
	fi
	# Otherwise, try to find the best compose file to link to
	if [ -f "$path/docker-compose.yml" ]; then
		echo -e "Linking compose file: $(format_path "$path/docker-compose.yml")"
		ln -sf "$path/docker-compose.yml" "$compose_file"
	elif [ -f "$path/docker-compose-default.yml" ]; then
		echo -e "Linking compose file: $(format_path "$path/docker-compose-default.yml")"
		ln -sf "$path/docker-compose-default.yml" "$compose_file"
	elif [ -f "$compose_file" ]; then
		# Already exists as a link file
		echo -e "Keeping linked compose file: $(format_path "$(readlink -f "$compose_file")")"
	elif [ -f "$path/Dockerfile" ]; then
		# Generate a compose file in projects dir
		echo -e "┌── GENERATING FILE: $(format_path "$compose_file") ───"
		local compose_content=$(generate_compose_file_content)
		echo -e "$compose_content" > "$compose_file"  # write to file
		echo -e "$compose_content" | sed 's/^/│ /'
		echo -e "└─────────────────────────$(printf '─%.0s' $(seq 1 ${#compose_file}))"
		echo -e "Using generated compose file: $(format_path "$compose_file")"
	else
		if ! $option_quiet && prompt_yes_no "No compose file or Dockerfile found. Generate a Dockerfile in $path?"; then
			local dockerfile="$path/Dockerfile"
			echo -e "┌── GENERATING FILE: $(format_path "$dockerfile") ───"
			local dockerfile_fullcontent=""
			dockerfile_content+="FROM $DEFAULT_DOCKER_IMAGE\n"
			dockerfile_content+="WORKDIR /usr/src/app\n"
			dockerfile_content+="RUN corepack enable\n"
			dockerfile_content+="COPY . .\n"
			suggested_entrypoint="node index.js"
			if [ -f "$path/yarn.lock" ] || grep -q -s "packageManager: 'yarn" "$path/package.json"; then
				suggested_entrypoint="yarn start"
				dockerfile_content+="RUN yarn set version stable\n"
				dockerfile_content+="RUN yarn install\n"
			elif [ -f "$path/package.json" ]; then
				suggested_entrypoint="npm start"
				dockerfile_content+="RUN npm install\n"
			fi
			dockerfile_fullcontent+="$dockerfile_content"
			echo -e "$dockerfile_content" | sed 's/^/│ /'
			dockerfile_content=""
			read -p "> Entrypoint (e.g. $suggested_entrypoint): " entrypoint
			dockerfile_content+="ENTRYPOINT [\"${entrypoint// /\", \"}\"]\n"
			read -p "> Port (e.g. 8700 or 8700:8700 or leave blank to use default): " port
			if [ -n "$port" ]; then
				dockerfile_content+="EXPOSE $port\n"
			fi
			local envvar=""
			while true; do
				read -p "> New environment variable (type as 'KEY=value', leave blank to finish): " envvar
				if [ -z "$envvar" ]; then
					break
				fi
				dockerfile_content+="ENV $envvar\n"
			done
			if [ -z "$envvar" ]; then
				dockerfile_content+="# ENV NODE_ENV=production\n"
			fi
			dockerfile_fullcontent+="$dockerfile_content"
			echo -e "$dockerfile_content"
			echo -e "└─────────────────────────$(printf '─%.0s' $(seq 1 ${#dockerfile}))"
			if prompt_yes_no "Do you want to edit the Dockerfile?"; then  # ask first, so user can Ctrl-C out
				echo -e "$dockerfile_fullcontent" > "$dockerfile"  # write to file
				${EDITOR:-vi} "$dockerfile"
			else
				echo -e "$dockerfile_fullcontent" > "$dockerfile"  # write to file
			fi
			# Now generate compose file
			echo -e "┌── GENERATING FILE: $(format_path "$compose_file") ───"
			local compose_content=$(generate_compose_file_content)
			echo -e "$compose_content" | sed 's/^/│ /'
			echo -e "└─────────────────────────$(printf '─%.0s' $(seq 1 ${#compose_file}))"
			if prompt_yes_no "Do you want to edit the docker compose file?"; then  # ask first, so user can Ctrl-C out
				echo -e "$compose_content" > "$compose_file"  # write to file
				${EDITOR:-vi} "$compose_file"
			else
				echo -e "$compose_content" > "$compose_file"  # write to file
			fi
			echo -e "Using generated compose file: $(format_path "$compose_file")"
		else
			$option_quiet && echo "To generate a Dockerfile, run this command without -q."
			compose_file=""
			return 1
		fi
	fi
}

# Utility: check if the compose file (link or file) exists for the project
check_compose_file() {  # args: none, reads: $project_name, sets: $compose_file
	compose_file="$PROJECTS_DIR/$project_name.docker-compose.yml"
	if [ ! -f "$compose_file" ]; then
		return 1
	fi
}

# Utility: Ensure a canonical symlinked service file exists for the project, generating or linking as needed.
select_service_file() {  # args: none, reads: $project_name $path, sets: $service_file
	service_file="$PROJECTS_DIR/$project_name.service"
	# If already a regular file itself (not a symlink), use it
	if [ -f "$service_file" ] && [ ! -L "$service_file" ]; then
		echo "Using service file: $service_file"
	fi
	# Otherwise, try to find the best service file to link to
	if [ -f "$PROJECTS_DIR/$project_name.service" ]; then
		echo "Linking service file: $PROJECTS_DIR/$project_name.service"
		ln -sf "$PROJECTS_DIR/$project_name.service" "$service_file"
	elif [ -f "$path/default.service" ]; then
		echo "Linking service file: $path/default.service"
		ln -sf "$path/default.service" "$service_file"
	elif [ -f "$service_file" ]; then
		# Already exists as a link file
		echo "Keeping linked service file: $(readlink -f "$service_file")"
	else
		if ! $option_quiet && prompt_yes_no "No service file found. Generate one?"; then
			local servicefile="$PROJECTS_DIR/$project_name.service"
			echo "┌── GENERATING FILE: $servicefile ───"
			local service_content=""
			service_content+="# Auto-generated by JeredMgr\n"
			service_content+="[Unit]\n"
			service_content+="Description=$project_name (managed by JeredMgr)\n"
			service_content+="After=network.target\n"
			service_content+="\n"
			service_content+="[Service]\n"
			service_content+="Type=simple\n"
			service_content+="User=$USER\n"
			service_content+="WorkingDirectory=$path\n"
			echo -e "$service_content" > "$servicefile"  # write to file
			echo -e "$service_content" | sed 's/^/│ /'
			service_content=""
			local startcmd
			read -p "> Start command (absolute or relative to $path): " startcmd
			service_content+="ExecStart=$startcmd\n"
			service_content+="Restart=always\n"
			while true; do
				read -p "> New environment variable (type as 'KEY=value', leave blank to finish): " service_envvar
				if [ -z "$service_envvar" ]; then
					break
				fi
				service_content+="Environment=\"$service_envvar\"\n"
			done
			service_content+="\n"
			service_content+="[Install]\n"
			service_content+="WantedBy=multi-user.target\n"
			echo -e "$service_content" >> "$servicefile"  # append to file
			echo -e "$service_content" | sed 's/^/│ /'
			echo "└─── $servicefile ───────────────────"
			if prompt_yes_no "Do you want to edit the service file?"; then
				${EDITOR:-vi} "$servicefile"
			fi
			echo "Linking service file: $servicefile"
			ln -sf "$servicefile" "$service_file"
		else
			$option_quiet && echo "To generate a service file, run this command without -q."
			service_file=""
			return 1
		fi
	fi
}

# Utility: check if the service file (link or file) exists for the project and the systemd service link points to it
check_service_file() {  # args: none, reads: $project_name, sets: $service_file
	service_file="$PROJECTS_DIR/$project_name.service"
	service_link="/etc/systemd/system/$project_name.service"
	if [ ! -f "$service_file" ] || [ "$(readlink -f "$service_link")" != "$service_file" ]; then
		return 1
	fi
}


# Utility: Prompt the user for a yes/no answer and return 0 for yes, 1 for no.
prompt_yes_no() {  # args: $prompt, reads: none, sets: none
	local prompt="$1"
	while true; do
		local yn
		read -n 1 -p "$(echo -e "${ITALIC}${prompt}${RESET} (${BOLD}y${RESET}/${BOLD}n${RESET}): ")" yn
		case $yn in
			[Yy]*)
				echo ""
				return 0
				;;
			[Nn]*)
				echo ""
				return 1
				;;
			*)
				echo -e " - ${RED}Please answer ${BOLD}y${RESET}${RED} or ${BOLD}n${RESET}${RED}.${RESET}"
				;;
		esac
	done
}

# Utility: Check if a file is executable
check_executable() {  # args: $file, reads: none, sets: none
	local file="$1"
	if [ ! -x "$file" ]; then
		if ! $option_quiet && prompt_yes_no "File '$file' is not executable. Make it executable?"; then
			chmod +x "$file"
		else
			return 1
		fi
	fi
}

lasttitle=""
# Utility: Start a pass-through progress indicator
startprogress() {   # args: $title, reads: none, sets: $lasttitle
	lasttitle=$1
	echo "$lasttitle"
}
lastoutput=""
# Utility: Pass-through the current line of output from a command
showprogress() {   # args: $command $args..., reads: none, sets: $lastoutput
	lastoutput=""
	local prevlen=0

    local fifo=$(mktemp -u)
    mkfifo "$fifo"
    "$@" &> "$fifo" &  # in background
    local cmd_pid=$!

	while IFS= read -r line; do
		curlen=${#line}
		[[ $curlen -lt $prevlen ]] && printf "\r%-${prevlen}s"
		printf "\r$line"
		prevlen=$curlen
		lastoutput+="$line"$'\n'
	done < "$fifo"

	wait "$cmd_pid"
	local retval=$?

	printf "\r%-${prevlen}s\r"
	return $retval
}
# Utility: End a pass-through progress indicator
endprogress() {   # args: $statustext, reads: none, sets: $lasttitle
	printf "\e[A"  # cursor up
	if [ -n "$lasttitle" ]; then
		echo "$lasttitle" "$1"
	else
		echo "$1"
	fi
	lasttitle=""
}

# Utility: Run script
run_script() {  # args: $script, reads: $path, sets: none
	local script="$1"
	if ! check_executable "$path/$script"; then
		echo "Script '$path/$script' is not executable, skipping."
	else
		echo "Running $path/$script"
		"$path/$script" || { retval=$?; echo "Script $script failed with exit code $retval" 1>&2; return $retval; }
	fi
}


################################################################################
# Commands
################################################################################

# Command: Add a new project by prompting the user and creating a .env file.
add_project() {  # args: $project_name, reads: none, sets: $project_name $env_file $owner $repo $use_global_pat $local_pat $path $type $repo_url $repo_pat_url
	local project_name="$1"

	if $option_quiet; then
		format_error "Command 'add' cannot be called with --quiet."
		return 1
	fi

	if [ -z "$project_name" ]; then
		read -p "Project name: " project_name
	fi
	# Validate project name format
	if ! [[ "$project_name" =~ ^[a-z_][a-z_0-9]*$ ]]; then
		format_error "Project name must start with a lowercase letter or underscore and contain only lowercase letters, numbers, and underscores."
		return 1
	fi
	env_file="${PROJECTS_DIR}/${project_name}.env"
	if [ -f "$env_file" ]; then
		format_error "Project already exists."
		return 1
	fi

	read -p "GitHub owner: " owner
	read -p "GitHub repository name (default: $project_name): " repo
	if [ -z "$repo" ]; then
		repo=$project_name
	fi
	read -p "Subdirectory inside git repo (default: none): " subdir
	prompt_yes_no "Use global GitHub PAT?" && use_global_pat=true || use_global_pat=false
	local_pat=""
	if ! $use_global_pat; then
		read -p "Project-specific GitHub PAT (leave blank to use no PAT): " local_pat
	fi
	local default_path="$original_dir"
	if ! [[ "$original_dir" == *"/$project_name" ]]; then default_path+="/$project_name"; fi
	read -p "Project path (default: $default_path): " path
	if [ -z "$path" ]; then
		path="$default_path"
	fi
	type_checked=false
	type=""
	while ! $type_checked; do
		read -p "$([ -n "$type" ] && echo "Invalid type '$type', try again" || echo "Project type") (docker/service/scripts): " type
		check_project_type
	done

	repo_url="https://github.com/${owner}/${repo}.git"

	{
		echo "ENABLED=false"
		echo "REPO_URL=$repo_url"
		[ -n "$subdir" ] && echo "SUBDIR=$subdir"
		echo "USE_GLOBAL_PAT=$use_global_pat"
		echo "LOCAL_PAT=$local_pat"
		echo "PATH=$path"
		echo "TYPE=$type"
	} > "$env_file"

	format_success "Successfully added project $(format_project "$project_name")."
	echo -e "You can now enable and install it with \`${BOLD}$SCRIPT_NAME enable $project_name${RESET}\`."
}

# Command: Remove a project by deleting the .env file.
remove_project() {  # args: $project_name, reads: $env_file $project_name $enabled $gitpath $subdir $path, sets: $env_file
	load_project_values "$1" || return 1
	if $enabled; then
		format_error "Project $(format_project "$project_name") is enabled, please disable it first."
		return 1
	fi
	if ! $option_force && ! prompt_yes_no "Are you sure you want to remove project $(format_project "$project_name")?"; then
		echo "Cancelled."
		return
	fi
	rm -f "$env_file"
	rm -f "$PROJECTS_DIR/$project_name.docker-compose.yml"
	rm -f "$PROJECTS_DIR/$project_name.docker-compose.yml.bak"
	rm -f "$PROJECTS_DIR/$project_name.docker-compose.yml.bak2"
	rm -f "$PROJECTS_DIR/$project_name.service"

	# If using subdir, ask about removing the full git repo
	if [ -n "$subdir" ] && [ -d "$gitpath" ]; then
		if ! $option_quiet && prompt_yes_no "Do you want to remove the full git repository at $(format_path "$gitpath")?"; then
			rm -rf "$gitpath"
			# If project path is a symlink, remove it and create empty dir
			if [ -L "$path" ]; then
				rm -f "$path"
				mkdir -p "$path"
				echo -e "Removed symlink at $(format_path "$path") and created empty directory"
			fi
			echo -e "Removed git repository at $(format_path "$gitpath")"
		else
			echo -e "Git repository at $(format_path "$gitpath") kept for potential reuse."
		fi
	fi

	format_success "Successfully removed project $(format_project "$project_name")."
}

# Command: List a single project with its enabled status and path.
list_project() {  # args: $project_name, reads: $enabled $project_name $path, sets: none
	load_project_values "$1" || return 1
	local statusicon
	if $enabled; then
		local running_status=$(get_running_status)
		if [ "$running_status" = "Yes" ]; then
			statusicon="✓"
		elif [ "$running_status" = "No" ]; then
			statusicon="⏹"
		else
			statusicon="?"
		fi
	else
		statusicon="✗"
	fi
	echo -e "$(format_status "$statusicon") $(format_project "$project_name"): $(format_path "$path")"
}

# Utility: Run setup.sh if present and perform type-specific install/setup logic for the project.
run_install() {  # args: none, reads: $repo_url $use_global_pat $local_pat $path $type $project_name $gitpath $subdir, sets: none
	# check if type is supported
	if ! $type_checked; then
		format_warning "Unknown or unsupported type '$type', skipping install."
		return 1
	fi


	if [ -n "$subdir" ]; then  # Subdir mode: full repo is inside projects dir
		# Check if we need to move an existing git repo
		if [ ! -d "$gitpath" ] && [ -d "$path" ] && check_git_path "$path"; then
			# If project is enabled, require disable first
			if $enabled; then
				format_error "Found existing git repository at $(format_path "$path"), cannot move to $(format_path "$gitpath") while project is enabled, please disable it first."
				return 1
			fi
			echo "Found existing git repository at $(format_path "$path"), moving to $(format_path "$gitpath") ..."
			mkdir -p "$(dirname "$gitpath")"
			mv "$path" "$gitpath" || { format_error "Failed to move git repository."; return 1; }
		fi
	fi

	# Create or verify gitpath (for both subdir and non-subdir mode)
	if [ ! -d "$gitpath" ] || [ -z "$(ls -A "$gitpath" 2>/dev/null)" ]; then
		repo_pat_url=$(get_repo_pat_url "$repo_url" "$use_global_pat" "$local_pat") || { echo "Could not get repository PAT URL." 1>&2; return 1; }
		echo "Cloning $repo_url $([ "$repo_url" != "$repo_pat_url" ] && echo "using PAT") into $(format_path "$gitpath") ..."
		mkdir -p "$(dirname "$gitpath")"
		git clone "$repo_pat_url" "$gitpath" || { format_error "Clone failed. Check credentials and repository access."; return 1; }
	elif ! check_git_path "$gitpath"; then
		format_error "Directory $(format_path "$gitpath") exists but is not a git repository."
		return 1
	fi

	if [ -n "$subdir" ]; then  # Subdir mode: full repo is inside projects dir
		# Verify subdir exists in the repository
		if [ ! -d "$gitpath/$subdir" ]; then
			format_error "Specified subdirectory $(format_path "$subdir") not found in repository at $(format_path "$gitpath")."
			return 1
		fi

		# Create or update symlink
		if [ -L "$path" ]; then
			local current_target=$(readlink -f "$path")
			local expected_target=$(readlink -f "$gitpath/$subdir")
			if [ "$current_target" != "$expected_target" ]; then
				echo "Fixing symlink $(format_path "$path") to point to $(format_path "$gitpath/$subdir")"
				rm "$path"
				ln -sf "$gitpath/$subdir" "$path"
			fi
		else
			if [ -d "$path" ]; then
				format_error "Path $(format_path "$path") exists but is not a symlink, cannot link to specified repo subdir."
				return 1
			fi
			echo "Creating symlink from $(format_path "$path") to $(format_path "$gitpath/$subdir")"
			mkdir -p "$(dirname "$path")"
			ln -sf "$gitpath/$subdir" "$path"
		fi
	fi

	did_run_setup=false
	# run setup.sh if exists for all project types
	if [ -f "$path/setup.sh" ]; then
		run_script "setup.sh" || return 1;
		did_run_setup=true
	fi

	# run type-specific install/setup logic
	case "$type" in
		docker)
			if ! select_compose_file; then
				format_error "No docker compose file could be determined."
				return 1
			fi
			echo "Building possible docker images ..."
			docker compose -f "$compose_file" --project-directory "$path" build
			;;
		service)
			if ! select_service_file; then
				format_error "No service file could be determined."
				return 1
			fi

			service_link="/etc/systemd/system/$project_name.service"
			if [ -f "$service_link" ] && [ "$(readlink -f "$service_link")" != "$service_file" ]; then
				format_error "A service file already exists at $(format_path "$service_link"), cannot install $(format_project "$project_name")."
				return 1
			fi
			if [ ! -L "$service_link" ]; then
				ln -sf "$service_file" "$service_link" || { format_error "Failed to link service file $(format_path "$service_link") to $(format_path "$service_file")"; return 1; }
				echo "Linked service file $(format_path "$service_link") to $(format_path "$service_file")"
			else
				echo "Service file $(format_path "$service_link") already linked to $(format_path "$service_file")"
			fi

			echo "Reloading systemd daemon ..."
			systemctl daemon-reload
			;;
		scripts)
			if ! $did_run_setup; then
				format_warning "No $(format_path "setup.sh") script found in $(format_path "$path"), only setting ENABLED=true."
			fi
			;;
	esac
}

# Command: Enable a project by running install/setup and setting ENABLED=true in the .env file.
enable_project() {  # args: $project_name, reads: $env_file, sets: none
	load_project_values "$1" || return 1
	if ! run_install; then
		format_error "Install failed with project $(format_project "$project_name"), $($enabled && echo "disabling project" || echo "project remains disabled")"
		write_env_value "ENABLED" "false"
		return 1
	fi
	if $enabled; then
		format_success "Successfully re-installed project $(format_project "$project_name"), it was already enabled."
	else
		write_env_value "ENABLED" "true"
		format_success "Successfully installed and enabled project $(format_project "$project_name")."
	fi
	if $enabled && [ "$(get_running_status)" = "Yes" ]; then
		echo "Restarting project $(format_project "$project_name") now."
		restart_project "$project_name" || return 1
	else
		echo -e "You can now start it with \`${BOLD}$SCRIPT_NAME start $project_name${RESET}\`."
	fi
}

# Command: Disable and uninstall a project, performing type-specific cleanup and setting ENABLED=false.
disable_project() {  # args: $project_name, reads: $env_file $type $path, sets: none
	load_project_values "$1" || return 1
	if ! $enabled; then
		format_warning "Already disabled, skipping."
		return
	fi
	if ! $type_checked; then
		format_warning "Unknown or unsupported type '$type', skipping uninstall."
	else
		case "$type" in
			docker)
				if ! check_compose_file; then
					format_warning "No valid docker compose file found, possibly already uninstalled."
				else
					if grep -q '# Auto-generated by JeredMgr, will remove images on uninstall' "$compose_file"; then
						echo "Stopping possibly running docker containers and removing images ..."
						docker compose -f "$compose_file" --project-directory "$path" down --rmi all
						if [ -f "$compose_file" ]; then
							# Check if compose file was auto-generated and matches current content
							if [ $(cat "$compose_file") = $(generate_compose_file_content) ]; then
								rm "$compose_file"
							else
								mv "$compose_file.bak" "$compose_file.bak2" 2>/dev/null
								mv "$compose_file" "$compose_file.bak"
								echo "Created backup of compose file to $(format_path "$compose_file.bak")."
							fi
						fi
					else
						echo "Stopping possibly running docker containers ..."
						docker compose -f "$compose_file" --project-directory "$path" down
					fi
				fi
				;;
			service)
				if ! check_service_file; then
					if systemctl status "$project_name" > /dev/null 2>&1; then
						format_warning "Warning: No valid project service file found, but found systemd service $(format_project "$project_name")! There might be another service with the same name!"
					else
						format_warning "No valid service file and no systemd service found, possibly already uninstalled."
					fi
				else
					echo "Stopping systemd service $(format_project "$project_name") ..."
					systemctl stop "$project_name"
					rm -f "$service_link"
					echo -e "Removed service file link $(format_path "$service_link")."
				fi
				echo "Reloading systemd daemon ..."
				systemctl daemon-reload
				;;
			scripts)
				if [ -f "$path/uninstall.sh" ]; then
					run_script "uninstall.sh" || return 1;
				else
					format_warning "No uninstall.sh script found in $path, only setting ENABLED=false."
				fi
				;;
		esac
	fi
	write_env_value "ENABLED" "false"
	format_success "Successfully $($type_checked && echo "uninstalled and disabled" || echo "disabled") project $(format_project "$project_name")."
}

# Utility: Get the running status of a project: Yes, No, Unknown. (run in subshell, don't use format_ functions here!)
get_running_status() {  # args: none, reads: $type $path $project_name, sets: none
	case "$type" in
		docker)
			if ! check_compose_file; then
				echo "Unknown"
				return
			else
				running=$(docker compose -f "$compose_file" --project-directory "$path" ps --services --filter status=running 2>/dev/null) || running=""
				[ -n "$running" ] && echo "Yes" || echo "No"
			fi
			;;
		service)
			if ! check_service_file; then
				echo "Unknown"
				return
			else
				active=$(systemctl is-active "$project_name" 2>/dev/null) || active=""
				[ "$active" = "active" ] && echo "Yes" || echo "No"
			fi
			;;
		scripts)
			echo "Unknown"
			;;
	esac
}


# Command: Start a project if enabled, using the appropriate method for its type.
start_project() {  # args: $project_name, reads: $enabled $type $path $project_name, sets: none
	load_project_values "$1" || return 1
	if ! $enabled; then
		format_warning "Not enabled, skipping start."
		return
	fi
	if ! $type_checked; then
		format_warning "Unknown or unsupported type '$type', skipping start."
		return 1
	fi
	local running_status=$(get_running_status)
	if [ "$running_status" = "Yes" ] && ! $option_force && ($option_quiet || ! prompt_yes_no "Project seems to be running. Trigger start anyway?"); then
		echo "Already running, skipping start."
		return
	fi
	local check_status=false
	case "$type" in
		docker)
			if ! check_compose_file; then
				format_error "No valid docker compose file found, cannot start."
				return 1
			fi
			docker compose -f "$compose_file" --project-directory "$path" up -d
			check_status=true
			;;
		service)
			if ! check_service_file; then
				format_error "No valid service file found, cannot start."
				return 1
			fi
			systemctl start "$project_name"
			check_status=true
			;;
		scripts)
			if [ -f "$path/start.sh" ]; then
				run_script "start.sh" || return 1;
			else
				format_error "No $(format_path "start.sh") script found in $(format_path "$path")."
				return 1
			fi
			;;
	esac

	if ! $check_status; then
		format_success "Project $(format_project "$project_name") started."
		return
	fi

	local i=0
	local max_retries=$STATUS_CHECK_RETRIES
	if $option_no_status_check; then
		max_retries=0
	fi
	while [ $i -le $max_retries ]; do
		[ $i -gt 0 ] && sleep 0.1
		running_status=$(get_running_status)
		if [ "$running_status" = "Yes" ]; then
			format_success "Successfully started project $(format_project "$project_name")."
			return
		fi
		((i++))
	done
	if [ "$running_status" = "No" ]; then
		format_error "Failed to start project $(format_project "$project_name"), still not running after $(((i - 1) * 100))ms timeout."
	else
		format_warning "Running status unknown for project $(format_project "$project_name")."
	fi
	return 1
}

# Command: Stop a project using the appropriate method for its type.
stop_project() {  # args: $project_name, reads: $type $path $project_name, sets: none
	load_project_values "$1" || return 1
	if ! $type_checked; then
		format_warning "Unknown or unsupported type '$type', skipping stop."
		return 1
	fi
	local running_status=$(get_running_status)
	if [ "$running_status" = "No" ] && ! $option_force && ($option_quiet || ! prompt_yes_no "Project seems to be stopped. Trigger stop anyway?"); then
		echo "Already stopped, skipping stop."
		return
	fi
	local check_status=false
	case "$type" in
		docker)
			if ! check_compose_file; then
				format_error "No valid docker compose file found, cannot stop."
				return 1
			fi
			docker compose -f "$compose_file" --project-directory "$path" down
			check_status=true
			;;
		service)
			if ! check_service_file; then
				format_error "No valid service file found, cannot stop."
				return 1
			fi
			systemctl stop "$project_name"
			check_status=true
			;;
		scripts)
			if [ -f "$path/stop.sh" ]; then
				run_script "stop.sh" || return 1;
			else
				format_error "No $(format_path "stop.sh") script found in $(format_path "$path")."
				return 1
			fi
			;;
	esac

	if ! $check_status; then
		format_success "Project $(format_project "$project_name") stopped."
		return
	fi

	local i=0
	local max_retries=$STATUS_CHECK_RETRIES
	if $option_no_status_check; then
		max_retries=0
	fi
	while [ $i -le $max_retries ]; do
		[ $i -gt 0 ] && sleep 0.1
		running_status=$(get_running_status)
		if [ "$running_status" = "No" ]; then
			format_success "Successfully stopped project $(format_project "$project_name")."
			return
		fi
		i=$((i + 1))
	done
	if [ "$running_status" = "Yes" ]; then
		format_error "Failed to stop project $(format_project "$project_name"), still running after $(((i - 1) * 100))ms timeout."
	else
		format_warning "Running status unknown for project $(format_project "$project_name")."
	fi
	return 1
}

# Command: Restart a project if enabled, using the appropriate method for its type.
restart_project() {  # args: $project_name, reads: $enabled $type $path $project_name, sets: none
	load_project_values "$1" || return 1
	if ! $enabled; then
		format_warning "Not enabled, skipping restart."
		return
	fi
	if ! $type_checked; then
		format_warning "Unknown or unsupported type '$type', skipping restart."
		return 1
	fi
	case "$type" in
		docker)
			if ! check_compose_file; then
				format_error "No valid docker compose file found, cannot restart."
				return 1
			fi
			docker compose -f "$compose_file" --project-directory "$path" down
			docker compose -f "$compose_file" --project-directory "$path" up -d
			;;
		service)
			if ! check_service_file; then
				format_error "No valid service file found, cannot restart."
				return 1
			fi
			systemctl restart "$project_name"
			;;
		scripts)
			if [ -f "$path/restart.sh" ]; then
				run_script "restart.sh" || return 1;
			elif [ -f "$path/stop.sh" ] && [ -f "$path/start.sh" ]; then
				run_script "stop.sh" || return 1;
				run_script "start.sh" || return 1;
			else
				format_error "No $(format_path "restart.sh") or $(format_path "start.sh") + $(format_path "stop.sh") scripts found in $(format_path "$path")."
				return 1
			fi
			;;
	esac
	format_success "Successfully restarted project $(format_project "$project_name")."
}

# Command: Show the status of a project, including enabled/running state and git status.
status_project() {  # args: $project_name, reads: $enabled $type $path $project_name $repo_url $use_global_pat $local_pat $all_projects $gitpath, sets: none
	load_project_values "$1" || return 1
	echo -e "Enabled: $(format_status "$($enabled && echo "✓" || echo "✗")")"
	if ! $type_checked; then
		format_warning "Unknown or unsupported type '$type', skipping status."
		return 1
	fi
	case "$type" in
		docker)
			running_status=$(get_running_status)
			echo -e "Running: $(format_status "$running_status")"
			if ! check_compose_file; then
				echo -e "Docker compose file: ${RED}Not found${RESET}"
			else
				echo -e "Docker compose file: $(format_path "$compose_file")$([ -L "$compose_file" ] && echo " (→ $(format_path "$(readlink -f "$compose_file")"))")"
			fi
			;;
		service)
			running_status=$(get_running_status)
			echo -e "Running: $(format_status "$running_status")"
			if ! check_service_file; then
				echo -e "Service file: ${RED}Not found${RESET}"
			else
				echo -e "Service file: $(format_path "$service_file")$([ -L "$service_file" ] && echo " (→ $(format_path "$(readlink -f "$service_file")"))")"
			fi
			;;
		scripts)
			if [ -f "$path/status.sh" ]; then
				run_script "status.sh" || return 1;
			else
				format_warning "No $(format_path "status.sh") script found in $(format_path "$path")."
			fi
			;;
	esac
	echo -e "Project path: $(format_path "$path")"
	echo -e "Repository: $(format_path "$repo_url")"
	if [ -n "$subdir" ]; then
		echo -e "Subdirectory: $(format_path "$subdir")"
	fi
	if $use_global_pat; then
		echo "Authentication: Using global PAT"
	elif [ -n "$local_pat" ]; then
		echo "Authentication: Using project-specific PAT"
	else
		echo "Authentication: Public repository or globally configured"
	fi
	# Check for git updates
	echo -n "Git status: "
	if check_git_path "$gitpath"; then
		local error_msg=$(check_git_upstream "$gitpath" 2>&1)
		if [ $? -eq 0 ]; then
			echo -e "${GREEN}Up to date!${RESET}$([ $type = "docker" ] && echo " (There might be new docker images available though)")"
		else
			format_warning "${error_msg:-Update available}"
		fi
	else
		format_warning "Git repository not set up!"
	fi

	if ! $all_projects && ( [ "$type" = "docker" ] || [ "$type" = "service" ] ); then
		echo ""
		case "$type" in
			docker)
				docker compose -f "$compose_file" --project-directory "$path" ps -a
				;;
			service)
				systemctl status "$project_name" --no-pager -n 0
				;;
		esac
	fi
}

# Command: Show logs for a project using the appropriate method for its type.
logs_project() {  # args: $project_name, reads: $type $path $project_name $all_projects $parameter_lines, sets: none
	load_project_values "$1" || return 1
	if ! $type_checked; then
		format_warning "Unknown or unsupported type '$type', skipping logs."
		return 1
	fi
	case "$type" in
		docker)
			if ! check_compose_file; then
				format_warning "No valid docker compose file found, cannot show logs."
				return 1
			fi
			docker compose -f "$compose_file" --project-directory "$path" logs $(! $all_projects && [ "$parameter_lines" = "f" ] && echo "-f" || echo "-n ${parameter_lines//f/$LOG_LINES}")
			;;
		service)
			if ! check_service_file; then
				format_warning "No valid service file found, cannot show logs."
				return 1
			fi
			journalctl -u "$project_name" $(! $all_projects && [ "$parameter_lines" = "f" ] && echo "-f" || echo "-n ${parameter_lines//f/$LOG_LINES}")
			;;
		scripts)
			if [ -f "$path/logs.sh" ]; then
				run_script "logs.sh" || return 1;
			else
				format_warning "No $(format_path "logs.sh") script found in $(format_path "$path")."
				return 1
			fi
			;;
	esac
}

# Command: Open a shell in the project container (docker only).
shell_project() {  # args: $project_name, reads: $enabled $type $path $project_name, sets: none
	load_project_values "$1" || return 1
	if [ "$type" != "docker" ]; then
		format_error "Shell command is only available for docker projects."
		return 1
	fi
	if ! $enabled; then
		format_error "Project is not enabled, cannot open shell."
		return 1
	fi
	if ! check_compose_file; then
		format_error "No valid docker compose file found, cannot open shell."
		return 1
	fi

	# Check if container is running
	local running_status=$(get_running_status)
	if [ "$running_status" != "Yes" ]; then
		format_error "Container is not running, cannot open shell."
		return 1
	fi

	# Get all service names from docker-compose.yml
	local services=$(docker compose -f "$compose_file" --project-directory "$path" ps --services)
	if [ -z "$services" ]; then
		format_error "Could not determine service names from docker compose file."
		return 1
	fi

	# Count number of services
	local service_count=$(echo "$services" | wc -l)
	
	if [ "$service_count" -eq 1 ]; then
		# If only one service, use it directly
		local service_name="$services"
	else
		# If multiple services, allow user to select by prefix
		if $option_quiet; then
			echo "Multiple services found, using first one (run without -q next time to choose):"
			echo "$services"
			service_name=$(echo "$services" | head -n1)
		else
			echo "Multiple services found:"
			echo "$services"
			read -p "Enter (start of) service name: " prefix

			# First check for exact match
			local exact_match=$(echo "$services" | grep -x "$prefix")
			if [ -n "$exact_match" ]; then
				service_name="$prefix"
			else
				# If no exact match, look for prefix matches
				local matches=$(echo "$services" | grep "^$prefix")
				local match_count=$(echo "$matches" | wc -l)
				
				if [ -z "$matches" ]; then
					format_error "No services match '$prefix*'!"
					return 1
				elif [ "$match_count" -eq 1 ]; then
					service_name="$matches"
				else
					format_error "Provided service name is ambiguous!"
					return 1
				fi
			fi
		fi
	fi

	format_header "Opening container-shell for project $(format_project "$project_name") service ${DARKGRAY}$service_name${RESET}:"
	docker compose -f "$compose_file" --project-directory "$path" exec "$service_name" sh -l
}

is_manager_updating=false
did_update=false
# Command: Update the git repository for a project.
update_git_repo() {  # args: none, reads: $gitpath $repo_url $use_global_pat $local_pat, sets: none
	did_update=false
	if ! check_git_path "$gitpath"; then
		format_warning "Path is not a git repository, skipping git repository update."
		return
	fi
	repo_pat_url=$(get_repo_pat_url "$repo_url" "$use_global_pat" "$local_pat")
	echo "Fetching updates ..."
	git -C "$gitpath" fetch --quiet || { echo "Failed to fetch upstream" 1>&2; return 1; }
	local previous_hash=$(git -C "$gitpath" rev-parse --short HEAD 2>/dev/null)
	local local_branch=$(git -C "$gitpath" rev-parse --abbrev-ref HEAD 2>/dev/null)
	local upstream_ref=$(git -C "$gitpath" rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null) || { echo "No upstream configured" 1>&2; return 1; }
	local remote_name=$(echo "$upstream_ref" | cut -d'/' -f1)
	local remote_branch=$(echo "$upstream_ref" | cut -d'/' -f2-)
	local behind=$(git -C "$gitpath" rev-list --count "$local_branch..$upstream_ref" 2>/dev/null) || {
		format_error "Failed to get commit count"
		return 1
	}
	if ! [[ "$behind" =~ ^[0-9]+$ ]]; then
		format_error "Invalid commit count returned by git ($behind)"
		return 1
	fi
	if [ "$behind" -eq 0 ]; then
		format_success "$($is_manager_updating && echo "JeredMgr" || echo "Git repository") is already up to date$($is_manager_updating && echo " ($VERSION)")!"
	else
		echo "Updating $($is_manager_updating && echo "JeredMgr from $VERSION" || echo "git repository") ($behind commits behind) ..."
		startprogress ""
		showprogress git -C "$gitpath" pull "$repo_pat_url" || {
			endprogress "$(format_error "Update failed with exit code $?!")"
			echo "$lastoutput"
			return 1
		}
		local current_hash=$(git -C "$gitpath" rev-parse --short HEAD 2>/dev/null)
		if $is_manager_updating; then
			endprogress "$(format_success "Self-update complete from $previous_hash to $current_hash")"
		else
			endprogress "$(format_success "Successfully updated git repository from $previous_hash to $current_hash")"
		fi
		did_update=true
	fi
}

dangling_docker_images=""
dangling_docker_hashes=""
# Utility: Update docker images if the project is a docker project.
update_docker_images() {
	if [ $type = "docker" ] && check_compose_file; then
		# pull images separately to track whether something was updated instead of `docker compose pull`
		local config_output=$(docker compose -f "$compose_file" --project-directory "$path" config 2>/dev/null) || {
			format_error "Failed to get docker compose config"
			return 1
		}
		local images=$(echo "$config_output" | grep -E '^[ \t]+image: ' | awk '{ sub(/^[ \t]+image: +/, ""); sub(/[ \t].*$/, ""); print }')
		if [ -z "$images" ]; then
			format_warning "No images to possibly update found in docker compose file."
		else
			echo "Checking for new docker images:"
			local updated=0
			local new_dangling=""
			local new_dangling_hashes=""
			while IFS= read -r image; do
				[ -n "$image" ] || continue
				startprogress "  - ${image}:"
				showprogress docker image pull "$image" || {
					endprogress "$(format_error "Update failed with exit code $?!")"
					echo "$lastoutput"
					return 1
				}
				if echo "$lastoutput" | grep -q "Status: Image is up to date"; then
					endprogress "$(format_success "Already up to date")"
				else
					endprogress "$(format_success "Updated successfully")"
					((updated++))
				fi
                new_dangling+="$(docker images --format "  - {{.Repository}}:{{.Tag}} {{.ID}}" --filter "dangling=true" --filter "reference=${image%:*}")"$'\n'
				new_dangling_hashes+="$(docker images --format "{{.ID}}" --filter "dangling=true" --filter "reference=${image%:*}") "
			done <<< "$images"
			if [ -n "$new_dangling_hashes" ]; then
				echo "Obsolete (dangling) images will be listed at the end of the update(s)."
				dangling_docker_images+="# $project_name:\n$new_dangling"
				dangling_docker_hashes+="$new_dangling_hashes"
			fi
			if [ $updated -ne 0 ]; then
				format_success "Successfully updated $updated docker image(s)."
			else
				format_success "All docker images already up to date."
			fi
		fi
	fi
}

# Command: Update a project by pulling from git, running install/setup, and restarting if successful.
update_project() {  # args: $project_name, reads: $path $repo_url $use_global_pat $local_pat $project_name, sets: none
	load_project_values "$1" || return 1

	if [ -f "$path/update.sh" ]; then
		run_script "update.sh" || return 1;
	else
		update_git_repo || return 1
		update_docker_images || return 1
	fi

	if ! run_install; then
		format_error "Post-update install failed. Skipping restart."
		return 1
	fi

	echo ""
	format_success "Update complete."
	if [ "$(get_running_status)" = "Yes" ]; then
		echo "Restarting project after update ..."
		restart_project "$project_name" || return 1
	else
		echo "Project is not running, skipping restart."
	fi
}

# Command: Update the manager script itself from the remote repository.
self_update() {  # args: none, reads: none, sets: none
	if $option_internal_recursive; then
		format_success "Successfully updated JeredMgr to $VERSION."
		return
	fi
	gitpath=$(dirname "$0")
	repo_url="$SELFUPDATE_REPO_URL"
	use_global_pat=false
	local_pat=""
	is_manager_updating=true
	update_git_repo || { format_error "Failed to update JeredMgr."; return 1; }
	is_manager_updating=false

	if $did_update; then
		chmod +x "$0"
		echo "Restarting JeredMgr ..."
		"$0" "${original_args[@]}" --internal-recursive
		exit $?
	fi
}

################################################################################    
# MAIN
################################################################################

# Utility: loop through projects
for_each_project() {  # args: $action, reads: $project_name $projects_list $multiple_projects, sets: none
	local action="$1"
	local all_success=true

	local action_upper=$(echo "$action" | tr '[:lower:]' '[:upper:]')
	if ! $multiple_projects; then
		format_header "###   LIST selected project:  $(format_project "$project_name")   ###"
		${action}_project "$project_name" || all_success=false
	else
		if [ "$action" = "list" ]; then
			format_header "###   LIST $($all_projects && echo "all" || echo "selected") $(echo "$projects_list" | wc -l) projects   ###"
		fi
		local is_first=true
		while IFS= read -r project_name; do
			if [ "$action" != "list" ]; then
				if ! $is_first; then
					echo -e "${DIM}----------------------------------------${RESET}"
				fi
				is_first=false
				format_header "###   ${action_upper} for project:  $(format_project "$project_name")   ###"
			fi
			${action}_project "$project_name" || all_success=false
		done <<< "$projects_list"
	fi
	if ! $all_success; then return 1; fi
}

# Utility: Prompt the user to confirm multiple projects or error for single-project commands.
check_projects_arg() {  # args: $can_multiple $verb, reads: $project_name $option_quiet, sets: $all_projects $multiple_projects $projects_list
	local can_multiple="$1"
	local verb="$2"  # can be empty, then no confirmation is asked

	# Reset global variables
	all_projects=false
	multiple_projects=false
	projects_list=""

	if [ -z "$project_name" ]; then  # If no project name given, handle all projects case
		all_projects=true
		multiple_projects=true
		# Get all project names
		projects_list=$(ls -1 "$PROJECTS_DIR"/*.env 2>/dev/null | xargs -n1 basename -s .env)
		if [ -z "$projects_list" ]; then
			format_error "No projects found in $(format_path "$PROJECTS_DIR")."
			exit 1
		fi
		local count_projects=$(echo "$projects_list" | wc -l)
		if ! $can_multiple; then
			format_error "Please specify a project name!"
			exit 1
		fi
		if ! $option_quiet && [ -n "$verb" ]; then
			echo "Found $count_projects projects: $projects_list"
			prompt_yes_no "Are you sure you want to $verb ALL $count_projects projects?" || { echo "Cancelled."; exit 0; }
		fi
	elif [[ "$project_name" == *+* ]]; then  # Handle wildcard matching if project_name contains +
		local pattern=${project_name//+/.*}
		projects_list=$(ls -1 "$PROJECTS_DIR"/*.env 2>/dev/null | xargs -n1 basename -s .env | grep -E "^${pattern}$" || true)
		if [ -z "$projects_list" ]; then
			format_error "No projects match pattern '$project_name'!"
			exit 1
		fi
		local count_matches=$(echo "$projects_list" | wc -l)
		if [ $count_matches -eq 1 ]; then
			project_name="$projects_list"
			multiple_projects=false
		else
			if ! $can_multiple; then
				format_error "Pattern '$project_name' is ambiguous. Multiple matching projects:"
				echo "$projects_list" 1>&2
				exit 1
			fi
			multiple_projects=true
			if ! $option_quiet && [ -n "$verb" ]; then
				local total_projects=$(ls -1 "$PROJECTS_DIR"/*.env 2>/dev/null | wc -l)
				echo "Found $count_matches matching projects (of $total_projects total): $projects_list"
				prompt_yes_no "Are you sure you want to $verb these $count_matches projects?" || { echo "Cancelled."; exit 0; }
			fi
		fi
	elif [ ! -f "$PROJECTS_DIR/$project_name.env" ]; then  # Single project case
		format_error "Project $(format_project "$project_name") not found."
		exit 1
	else
		projects_list="$project_name"
		multiple_projects=false
	fi
}

original_args=("$@")
original_dir=$(pwd)
cd "$(dirname $(readlink -f "$0"))"
PROJECTS_DIR=$(readlink -f "$PROJECTS_DIR")
GLOBAL_PAT_FILE=$(readlink -f "$GLOBAL_PAT_FILE")

command=""
project_name=""
option_quiet=false
option_force=false
option_no_status_check=false
option_internal_recursive=false
parameter_lines="f"

exit_code=0

while [[ $# -gt 0 ]]; do
	case "$1" in
		-q|--quiet)
			option_quiet=true
			shift
			;;
		-f|--force)
			option_force=true
			shift
			;;
		-s|--no-status-check)
			option_no_status_check=true
			shift
			;;
		-n|--number-of-lines)
			if [ "$2" = "f" ] || [ "$2" = "follow" ]; then
				parameter_lines="f"
			elif [[ "$2" =~ ^[0-9]+$ ]]; then
				parameter_lines="$2"
			else
				format_error "Line count must be a number or 'f'/'follow'!"
				exit 1
			fi
			shift 2
			;;
		--internal-recursive)
			option_internal_recursive=true
			shift
			;;
		-*)
			format_error "Unknown option: '$1'!"
			list_commands
			exit 1
			;;
		*)
			if [ -z "$command" ]; then
				command="$1"
			elif [ -z "$project_name" ]; then
				project_name="$1"
			else
				format_error "Too many arguments: $1"
				list_commands
				exit 1
			fi
			shift
			;;
	esac
done

if [ -z "$command" ]; then
	echo "Welcome to JeredMgr $VERSION!"
	list_commands
	exit 1
fi

if [ "$command" = "help" ]; then
	show_help
	exit 0
fi

mkdir -p "$PROJECTS_DIR" || { format_error "Failed to create projects directory $(format_path "$PROJECTS_DIR")!"; exit 1; }
ensure_git_installed

case $command in
	add)
		# project name is optional on the command line, otherwise add_project will prompt for it
		add_project "$project_name" || exit_code=$?
		;;
	remove)
		# remove should need the full project name without wildcard, so we won't use check_projects_arg
		remove_project "$project_name" || exit_code=$?
		;;
	list)
		check_projects_arg true "" || exit 1
		for_each_project "list" || exit_code=$?
		;;
	enable)
		check_projects_arg true "enable" || exit 1
		for_each_project "enable" || exit_code=$?
		;;
	disable)
		check_projects_arg true "disable" || exit 1
		for_each_project "disable" || exit_code=$?
		;;
	start)
		check_projects_arg true "start" || exit 1
		for_each_project "start" || exit_code=$?
		;;
	stop)
		check_projects_arg true "stop" || exit 1
		for_each_project "stop" || exit_code=$?
		;;
	restart)
		check_projects_arg true "restart" || exit 1
		for_each_project "restart" || exit_code=$?
		;;
	status)
		check_projects_arg true "check status of" || exit 1
		for_each_project "status" || exit_code=$?
		;;
	logs)
		check_projects_arg true "show logs for" || exit 1
		for_each_project "logs" || exit_code=$?
		;;
	shell)
		check_projects_arg false "open shell for" || exit 1
		for_each_project "shell" || exit_code=$?
		;;
	update)
		check_projects_arg true "update" || exit 1
		if $all_projects; then  # First update manager script
            ! $option_internal_recursive && format_header "###   SELF-UPDATE   ###"
			self_update || exit_code=$?
			echo ""
		fi
		for_each_project "update" || exit_code=$?
		if [ -n "$dangling_docker_hashes" ]; then
			echo ""
			format_header "###   OBSOLETE DOCKER IMAGES   ###"
			echo "The following dangling docker images were found:"
			echo "$dangling_docker_images"
			! $option_quiet && prompt_yes_no "Do you want to remove them now?" && docker rmi -f $dangling_docker_hashes || echo "You can remove them later using ${BOLD}${DARKGRAY}\`docker rmi -f ${dangling_docker_hashes% }\`${RESET}"
		fi
		;;
	self-update)
		self_update || exit_code=$?
		;;
	*)
		format_error "Unknown command: '$command'!"
		list_commands
		exit 1
		;;
esac

exit $exit_code
