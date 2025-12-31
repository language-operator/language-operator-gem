# bash completion for langop

_langop_completions() {
    local cur prev words cword
    _init_completion || return

    # Helper function to get clusters
    _langop_clusters() {
        langop cluster list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v '^─' | grep -v '^NAME'
    }

    # Helper function to get agents
    _langop_agents() {
        langop agent list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v '^─' | grep -v '^NAME'
    }

    # Helper function to get personas
    _langop_personas() {
        langop persona list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v '^─' | grep -v '^NAME'
    }

    # Helper function to get tools
    _langop_tools() {
        langop tool list 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v '^─' | grep -v '^NAME'
    }

    # Top-level commands
    local commands="cluster use agent persona tool status version new serve test run console help"

    # Cluster subcommands
    local cluster_commands="create list current inspect delete"

    # Agent subcommands
    local agent_commands="create list inspect delete logs code edit pause resume"

    # Persona subcommands
    local persona_commands="list show create edit delete"

    # Tool subcommands
    local tool_commands="list install auth test delete"

    # If we're at the first argument
    if [[ $cword -eq 1 ]]; then
        COMPREPLY=($(compgen -W "$commands" -- "$cur"))
        return
    fi

    # Get the main command
    local cmd="${words[1]}"

    case "$cmd" in
        cluster)
            if [[ $cword -eq 2 ]]; then
                COMPREPLY=($(compgen -W "$cluster_commands" -- "$cur"))
            elif [[ $cword -eq 3 ]]; then
                case "${words[2]}" in
                    inspect|delete|current)
                        COMPREPLY=($(compgen -W "$(_langop_clusters)" -- "$cur"))
                        ;;
                esac
            fi
            ;;
        use)
            if [[ $cword -eq 2 ]]; then
                COMPREPLY=($(compgen -W "$(_langop_clusters)" -- "$cur"))
            fi
            ;;
        agent)
            if [[ $cword -eq 2 ]]; then
                COMPREPLY=($(compgen -W "$agent_commands" -- "$cur"))
            elif [[ $cword -eq 3 ]]; then
                case "${words[2]}" in
                    inspect|delete|logs|code|edit|pause|resume)
                        COMPREPLY=($(compgen -W "$(_langop_agents)" -- "$cur"))
                        ;;
                    list)
                        COMPREPLY=($(compgen -W "--all-clusters --cluster=" -- "$cur"))
                        ;;
                    create)
                        COMPREPLY=($(compgen -W "--cluster= --create-cluster= --persona= --dry-run" -- "$cur"))
                        ;;
                esac
            fi
            ;;
        persona)
            if [[ $cword -eq 2 ]]; then
                COMPREPLY=($(compgen -W "$persona_commands" -- "$cur"))
            elif [[ $cword -eq 3 ]]; then
                case "${words[2]}" in
                    show|edit|delete)
                        COMPREPLY=($(compgen -W "$(_langop_personas)" -- "$cur"))
                        ;;
                    create)
                        COMPREPLY=($(compgen -W "--from= --cluster=" -- "$cur"))
                        ;;
                esac
            fi
            ;;
        tool)
            if [[ $cword -eq 2 ]]; then
                COMPREPLY=($(compgen -W "$tool_commands" -- "$cur"))
            elif [[ $cword -eq 3 ]]; then
                case "${words[2]}" in
                    auth|test|delete)
                        COMPREPLY=($(compgen -W "$(_langop_tools)" -- "$cur"))
                        ;;
                    list)
                        COMPREPLY=($(compgen -W "--cluster=" -- "$cur"))
                        ;;
                esac
            fi
            ;;
        new)
            if [[ $cword -eq 2 ]]; then
                COMPREPLY=($(compgen -W "tool agent" -- "$cur"))
            fi
            ;;
    esac
}

complete -F _langop_completions langop
