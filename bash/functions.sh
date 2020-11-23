#!/bin/bash
# @DEPRECATED Use utils.sh
#
# Require: expect,ssh,openssl
# Reserved variable name: r_passphrase
#

function _usage() {
	echo "This script contains utility functions.
Executing this script with '-s' or '-u <ssh default user name>' set up your bash environment for ssh passhphrase authentication."
}

# set up ssh key, .bash_profile
function _setup() {
	local __doc__="Set up ssh key and bash profile.
If _default_ssh_user is not empty, also set up the default SSH username."
	local _default_ssh_user="$1"
	local _final_rc=0
	
	# Checking required commands
	local _requires="ssh,openssl"
	local _cmd_list=()
	_split "_cmd_list" "$_requires"
	for __cmd in "${_cmd_list[@]}"; do
		which $__cmd &>/dev/null || echo "ERROR: $__cmd might be missing." 1>&2
	done
	
	# copying this file under ~/bin/
	local _script_name=`basename $BASH_SOURCE`
	local _script_path="`which $_script_name`"
	if [ $? -ne 0 ]; then
		if [ ! -d "${HOME%/}/bin" ]; then
			echo "Creating ${HOME%/}/bin ..."
			mkdir -m 700 "${HOME%/}/bin"
		fi
		echo "Copying $BASH_SOURCE into ${HOME%/}/bin ..."
		cp $BASH_SOURCE ${HOME%/}/bin/
		chmod 700 ${HOME%/}/bin/$_script_name
	fi
	which $_script_name &>/dev/null || (echo "ERROR: Looks like $_script_name is not in $PATH" 1>&2; _final_rc=1)
	
	local _passphrase
	local _key_path="${HOME%/}/.ssh/id_rsa"
	read -p "Enter new passphrase (optional): " -s "_passphrase";
	echo ""
	if [ ! -s "$_key_path" ]; then
		echo "Looks like no private key. Generating..."
		ssh-keygen -f $_key_path -N "$_passphrase" || (echo "ERROR: generating private key failed." 1>&2; _final_rc=2)
	else
		# If private key already exist and only if r_passphrase is given, change passphrase
		if [ -n "$r_passphrase" ]; then
			local _old_passphrase="$(_deobfscate "$r_passphrase")"
			if [ "$_old_passphrase" != "$_passphrase" ]; then
				echo "New passphrase is different from Old passphrase. Resetting to NEW passhphrase..."
				ssh-keygen -f $_key_path -p -P $_old_passphrase -N $_passphrase || (echo "ERROR: resetting passphrase failed." 1>&2; _final_rc=3)
			fi
		fi
	fi
	
	# Editing .bash_profile
	grep -P "(^source|^\.) $_script_name" ${HOME%/}/.bash_profile &>/dev/null
	if [ $? -ne 0 ]; then
		echo "Inserting \"source $_script_name\" into ${HOME%/}/.bash_profile ..."
		echo "# ssh-agent, ssh-add automation" >> ${HOME%/}/.bash_profile
		echo "source $_script_name" >> ${HOME%/}/.bash_profile
		grep "^alias ssh_add" ${HOME%/}/.bash_profile &>/dev/null || echo "alias ssh_add='eval `ssh-agent` && ssh-add -l &>/dev/null || ssh-add'" >> ${HOME%/}/.bash_profile
		# cygwin does not have reset
		grep "^alias reset" ${HOME%/}/.bash_profile &>/dev/null || echo "alias reset='kill -WINCH $$'" >> ${HOME%/}/.bash_profile
	fi
	chmod 700 ${HOME%/}/.bash_profile
	grep "^alias ssh_add" ${HOME%/}/.bash_profile &>/dev/null || (echo "ERROR: could not update .bash_profile." 1>&2; _final_rc=4)
	
	# Set SSH default User name
	if [ -n "$_default_ssh_user" ]; then
		grep -i "^Host \*" ${HOME%/}/.ssh/config &>/dev/null
		if [ $? -ne 0 ] || [ ! -s "${HOME%/}/.ssh/config" ]; then
			echo -e "Host *\n    User $_default_ssh_user\n    StrictHostKeyChecking no\n    ForwardAgent yes" >> ${HOME%/}/.ssh/config
		else
			# FIXME: not perfect (how about comment or extra space in end?)
			grep -iP "^\s*User " ${HOME%/}/.ssh/config &>/dev/null
			if [ $? -ne 0 ]; then
				sed -i "/^^Host \*.*$/a     User $_default_ssh_user" ${HOME%/}/.ssh/config
			else
				echo "ERROR: Looks like some User is already specified in .ssh/config." 1>&2; _final_rc=5
			fi
		fi
	fi
	
	if [ $_final_rc -ne 0 ]; then
		echo "Setup completed but some ERROR(s) with return code $_final_rc"
	else
		echo "Setup completed with return code $_final_rc"
		echo "You may want to run 'ssh-copy-id "server1,server2,..." next."
	fi
	
	return $_final_rc
}

# set up ssh key, .bash_profile
function _setup_broken() {
	local __doc__="Set up ssh key and bash profile.
If _default_ssh_user is not empty, also set up the default SSH username."
	local _default_ssh_user="$1"
	local _final_rc=0
	
	# Checking required commands
	local _requires="expect,ssh,openssl"
	local _cmd_list=()
	_split "_cmd_list" "$_requires"
	for __cmd in "${_cmd_list[@]}"; do
		which $__cmd &>/dev/null || echo "ERROR: $__cmd might be missing." 1>&2
	done
	
	# copying this file under ~/bin/
	local _script_name=`basename $BASH_SOURCE`
	local _script_path="`which $_script_name`"
	if [ $? -ne 0 ]; then
		if [ ! -d "${HOME%/}/bin" ]; then
			echo "Creating ${HOME%/}/bin ..."
			mkdir -m 700 "${HOME%/}/bin"
		fi
		echo "Copying $BASH_SOURCE into ${HOME%/}/bin ..."
		cp $BASH_SOURCE ${HOME%/}/bin/
		chmod 700 ${HOME%/}/bin/$_script_name
	fi
	which $_script_name &>/dev/null || (echo "ERROR: Looks like $_script_name is not in $PATH" 1>&2; _final_rc=1)
	
	local _passphrase
	local _key_path="${HOME%/}/.ssh/id_rsa"
	read -p "Enter new passphrase: " -s "_passphrase";
	echo ""
	if [ ! -s "$_key_path" ]; then
		echo "Looks like no private key. Generating..."
		ssh-keygen -f $_key_path -N "$_passphrase" || (echo "ERROR: generating private key failed." 1>&2; _final_rc=2)
	else
		if [ -n "$r_passphrase" ]; then
			local _old_passphrase="$(_deobfscate "$r_passphrase")"
			if [ "$_old_passphrase" != "$_passphrase" ]; then
				echo "New passphrase is different from Old passphrase. Resetting to NEW passhphrase..."
				_expect "ssh-keygen -f $_key_path -N \"$_passphrase\" -p" "" "$_old_passphrase" || (echo "ERROR: resetting passphrase failed." 1>&2; _final_rc=3)
			fi
		fi
	fi
	
	# Editing .bash_profile
	r_passphrase="$(_obfscate "$_passphrase")"
	grep -P "(^source|^\.) $_script_name" ${HOME%/}/.bash_profile &>/dev/null
	if [ $? -ne 0 ]; then
		echo "Inserting \"source $_script_name\" into ${HOME%/}/.bash_profile ..."
		echo "# ssh-agent, ssh-add automation with expect" >> ${HOME%/}/.bash_profile
		echo "source $_script_name" >> ${HOME%/}/.bash_profile
		grep "^_ssh_agent" ${HOME%/}/.bash_profile &>/dev/null || echo "_ssh_agent \"${r_passphrase}\"" >> ${HOME%/}/.bash_profile
	else
		sed -i "s/^_ssh_agent.*$/_ssh_agent \"${r_passphrase}\"/" ${HOME%/}/.bash_profile
	fi
	chmod 700 ${HOME%/}/.bash_profile
	grep "^_ssh_agent" ${HOME%/}/.bash_profile &>/dev/null || (echo "ERROR: could not update .bash_profile." 1>&2; _final_rc=4)
	
	# Set SSH default User name
	if [ -n "$_default_ssh_user" ]; then
		grep -i "^Host \*" ${HOME%/}/.ssh/config &>/dev/null
		if [ $? -ne 0 ] || [ ! -s "${HOME%/}/.ssh/config" ]; then
			echo -e "Host *\n    User $_default_ssh_user\n    StrictHostKeyChecking no\n    ForwardAgent yes" >> ${HOME%/}/.ssh/config
		else
			# FIXME: not perfect (how about comment or extra space in end?
			grep -iP "^\s*User " ${HOME%/}/.ssh/config &>/dev/null
			if [ $? -ne 0 ]; then
				sed -i "/^^Host \*.*$/a     User $_default_ssh_user" ${HOME%/}/.ssh/config
			else
				echo "ERROR: Looks like some user is already specified in .ssh/config." 1>&2; _final_rc=5
			fi
		fi
	fi
	
	if [ $_final_rc -ne 0 ]; then
		echo "Setup completed but some ERROR(s) with return code $_final_rc"
	else
		echo "Setup completed with return code $_final_rc"
		echo "You may want to run '_ssh_copy_id "server1,server2,..." next."
	fi
	
	return $_final_rc
}

# Split _string and store into _rtn_var_name
function _split() {
	local _rtn_var_name="$1"
	local _string="$2"
	local _delimiter="${3-,}"
	local _original_IFS="$IFS"
	eval "IFS=\"$_delimiter\" read -a $_rtn_var_name <<< \"$_string\""
	local _return_rc=$?
	IFS="$_original_IFS"
	return $_return_rc
}

# obfuscate string
function _obfscate() {
	local _str="$1"
	local _return_rc=0
	
	#local _key="xxxxxxxxxxxxxxxxxxxxxxxx"
	#local _key_hex="$(echo -n "$_key" | xxd -p -c 256)"
	#local _result="$(echo -n "${_str}" | openssl enc -e -aes-256-ecb -nosalt -base64 -K ${_key_hex})"
	local _result="${g_prefix}$(echo -n "${_str}" | openssl base64 -e)"
	_return_rc=$?
	
	echo "${_result}"
	return $_return_rc
}

# obfuscate string
function _deobfscate() {
	local _str="$1"
	local _result="$str"
	local _return_rc=0
	
	if [ -n "$g_prefix" ]; then
		if [[ "${_str}" =~ ^${g_prefix} ]]; then
			_str="$(echo "${_str}" | sed -e "s/^${g_prefix}//")"
			_result="$(echo "${_str}" | openssl base64 -d)"
			_return_rc=$?
		fi
	fi
	
	echo "${_result}"
	return $_return_rc
}

function _multi_run() {
	local __doc__="Run one command against comma separated servers (or something).
The actual command will be like '{_comma_separated_str}{_node}{_command_after_str}',
Note that no space between before and after commands."
	local _comma_separated_str="$1"
	local _command="$2"
	local _run_in_bg=${3-false}
	
	local _last_rc=0
	local _tmp_out=""
	local _node_list=()
	local _cmd=""
	_split "_node_list" "$_comma_separated_str"
	for (( I = 0; I < ${#_node_list[@]}; ++I )); do
		_cmd="$(echo "$_command" | sed "s/%_NODE_%/${_node_list[$I]}/g")"
		
		if $_run_in_bg; then
			(_tmp_out="${_tmp_out}`eval "$_cmd" 2>&1`\n\n")&
		else
			eval "$_cmd"
		fi
		# not sure if this works when it's runnning in background...
		if [ $? -ne 0 ]; then
			_last_rc=$?
		fi
	done
	
	if $_run_in_bg; then
		wait
		echo -e "$_tmp_out"
	fi
	
	return $_last_rc
}

# Run generic expect
function _expect() {
	local _spawn_command="$1"
	local _commands="$2"
	local _passphrase="$3"
	local _password="$4"
	local _timeout="${5-1800}"
	local _last_rc=0
	
	if [ -z "$_spawn_command" ]; then
		echo "[$(date +"%Y-%m-%d %H:%M:%S %z")] ERROR: _spawn_command is mandatory for expect." 1>&2
		return 1
	fi
	
	if [ -z "$_passphrase" ] && [ -n "$r_passphrase" ]; then
		_password="$(_deobfscate "$r_passphrase")"
	fi
	
	if [ -z "$_password" ]; then
		_password="$_passphrase"
	fi
	
	local _expect_cmds=""
	local _prompt_regex="-re {[\$#] }"
	local _interactive="exit"
	local _log_user="log_user 1"
	
	if [ -n "$_commands" ]; then 
		local _commands_list=()
		_split "_commands_list" "$_commands" ";"
		local _ttl_cmds=${#_commands_list[@]}
		for (( I = 0; I < $_ttl_cmds; ++I )); do
			# FIXME: not good enough
			if [[ "${_commands_list[$I]}" =~ ^(sudo|sudo -s|sudo su|sudo su -|su|su -|sh|bash|/bin/bash|/bin/sh)$ ]]; then
				_interactive="interact"
				# dodgy banner workaround
				if [ $I -eq 0 ] && [ $_ttl_cmds -gt 1 ]; then
					_log_user="log_user 0"
				else
					_log_user="log_user 1"
				fi
			else
				_log_user="log_user 1"
				_interactive="exit"
			fi
			
			_expect_cmds="${_expect_cmds}
$_log_user
expect {
	\"*nter passphrase *\" { send \"${_passphrase}\n\"; expect ${_prompt_regex} { send \"${_commands_list[$I]}\r\" } }
	\"*assword:*\" { send \"${_password}\n\"; expect ${_prompt_regex} { send \"${_commands_list[$I]}\r\" } }
	\"*password for*\" { send \"${_password}\n\"; expect ${_prompt_regex} { send \"${_commands_list[$I]}\r\" } }
	${_prompt_regex} { send \"${_commands_list[$I]}\r\" }
	eof { exit }
}"
		done
	else
		_interactive="exit"
		_expect_cmds="expect {
	\"*nter passphrase *\" { send \"${_passphrase}\n\" }
	\"*nter old passphrase:*\" { send \"${_passphrase}\n\" }
	\"*assword:*\" { send \"${_password}\n\" }
	\"*password for*\" { send \"${_password}\n\" }
	\"*you want to continue connecting*\" { send \"yes\n\"; expect { \"*assword:*\"; send \"${_password}\n\" \"*nter passphrase *\" send \"${_passphrase}\n\" } }
	${_prompt_regex} { interact }
	eof { exit }
}"
	fi
	
	_expect_cmds="${_expect_cmds}
expect {
	\"*nter passphrase *\" { send \"${_passphrase}\n\"; expect ${_prompt_regex} { $_interactive } }
	\"*assword:*\" { send \"${_password}\n\"; expect ${_prompt_regex} { $_interactive } }
	\"*password for*\" { send \"${_password}\n\"; expect ${_prompt_regex} { $_interactive } }
	${_prompt_regex} { $_interactive }
	eof { exit }
}"
	
	# FIXME: disable login banner
	#expect -d-c "
	expect -c "
set timeout ${_timeout}
spawn -noecho ${_spawn_command}
$_expect_cmds"
	
	_last_rc=$?
	
	if [ $_last_rc -ne 0 ]; then
		echo "[$(date +"%Y-%m-%d %H:%M:%S %z")] ERROR: expect $_command failed (${_last_rc})" 1>&2
		return $_last_rc
	fi
	
	return $_last_rc
}

# Run ssh with expect
function _ssh() {
	local __doc__="Run commands against one or multiple servers."
	local _commands="$1"
	local _user_at_servers="$2"
	local _passphrase="$3"
	local _password="$4"
	local _run_in_bg=${5-false}
	
	_multi_run "$_user_at_servers" "_expect \"ssh -q -t %_NODE_%\" \"$_commands\" \"$_passphrase\" \"$_password\"" $_run_in_bg
	return $?
}

# Run scp with expect
function _scp() {
	local __doc__="Run scp command against one or multiple servers."
	local _file_path="$1"
	local _user_at_server_remote_paths="$2"
	local _passphrase="$3"
	local _password="$4"
	local _run_in_bg=${5-false}
	
	_multi_run "$_user_at_server_remote_paths" "_expect \"scp -qC $_file_path %_NODE_%\" \"\" \"$_passphrase\" \"$_password\"" $_run_in_bg
	return $?
}

function __ssh_copy_id() {
	local __doc__="Run ssh_copy_id command against one or multiple servers."
	local _user_at_server="$1"
	local _password="$2"
	
	ssh -q -o 'BatchMode yes' ${_user_at_server} 'echo "SSH connection test."'
	if [ $? -eq 0 ] ; then
		return 0
	fi
	
	if [ -z "$_password" ]; then
		read -p "Password: " -s "_password";
		echo ""
	fi
	# if password is still empty, _expect uses Passphrase
	
	_expect "ssh-copy-id $_user_at_server" "" "" "$_password"
	return $?
}

function _ssh_copy_id() {
	local __doc__="Run scp command against only one server."
	local _user_at_servers="$1"
	local _password="$2"
	
	_multi_run "$_user_at_servers" "__ssh_copy_id \"%_NODE_%\" \"$_password\""
	return $?
}

# setup ssh-agent and ssh-add with expect
function _ssh_agent() {
	local __doc__="Start ssh-agent."
	local _passphrase="$1"
	local _expect_rc=0
	
	if [ -z "$SSH_AGENT_PID" ]; then
		eval `ssh-agent` > /dev/null
		if [ $? -ne 0 ]; then
			echo "$FUNCNAME: ssh-agent error." 1>&2
			return 1
		fi
	fi
	
	ssh-add -l >/dev/null
	if [ $? -ne 0 ]; then
		if [ -z "$_passphrase" ]; then
			if [ -z "$r_passphrase" ]; then
				read -p "Passphrase: " -s "_passphrase";
				echo ""
				echo ""
			else
				_passphrase="$(_deobfscate "$r_passphrase")"
			fi
		else
			_passphrase="$(_deobfscate "$_passphrase")"
		fi
		
		_expect "ssh-add" "" "$_passphrase" 1>/dev/null
		_expect_rc=$?
		
		if [ $_expect_rc -eq 0 ]; then
			if [ -n "$_passphrase" ]; then
				r_passphrase="$(_obfscate "$_passphrase")"
			fi
		else
			echo "$FUNCNAME failed (${_expect_rc})" 1>&2
		fi
	fi
	
	return $_expect_rc
}

function _retry() {
	local __doc__="Retry given command until return code is 0 or reaches to _retry_num."
	local _cmd="$1"
	local _retry_num="${2-10}"
	local _interval="${3-2}"
	
	#trap "exit" SIGINT
	trap "echo \"Press 'Ctrl-c' again to exit.\";tail -f /dev/null" SIGINT
	
	local _i=0
	local _rc=1
	
	while [ $_rc -ne 0 -a $_i -lt $_retry_num ]; do
		_i=$(($_i+1))
		
		echo "[$_i] $_cmd" 
		$_cmd
		_rc=$?
		sleep $_interval
		
		# FXIME: Maybe rsync has own trap?
		if [ $_rc == 130 ]; then
			echo ""
			echo "Keyboard Intruptted. Exiting..."
			break;
		fi
	done
	
	trap - SIGINT
	
	if [ $_i -eq $_retry_num ]; then
		echo "Hit maximum number of retries, giving up."
	fi
	
	return $_rc
}

function _set_config() {
	local _key="$1"
	local _val="$2"
	local _conf="$3"
	local _b="${4-#}"
	
	grep -w "^${_key}" $_conf &>/dev/null
	if [ $? -ne 0 ]; then
		echo "${_key} ${_b} ${_val}" >> $_conf
	else
		sed -i "/^${_key} *${_b}/ s/${_b}.*$/${_b} ${_val}/" $_conf
	fi
}

function _email() {
	local _send_to="$1"
	local _subject="$2"
	local _html_body="$3"
	local _send_from="$4"
	local _mail_body="<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01 Transitional//EN\" \"http://www.w3.org/TR/html4/loose.dtd\">
<html>
<head><title>${_subject}</title>
</head>
<body>
${_html_body}
</body>
</html>"
	
	if [ -n "$_send_from" ]; then
		_send_from="-a \"From: ${_send_from}\""
	fi
	
	echo -e "$_mail_body" | mail $_send_from -a "MIME-Version: 1.0" -a "Content-Type: text/html" -s "${_subject}" $_send_to
	return $?
}

function _getAfterFirstMatch() {
	local _regex="$1"
	local _file_path="$2"
	
	ls $_file_path 2>/dev/null | while read l; do
		local _line_num=`grep -m1 -nP "$_regex" "$l" | cut -d ":" -f 1`
		if [ -n "$_line_num" ]; then
			sed -n "${_line_num},\$p" "${l}"
		fi
	done
	return $?
}


g_prefix="a4ebZASw7ade"
if [ "$0" = "$BASH_SOURCE" ]; then
	r_ssh_default_username=""
	r_is_running_setup=false
	while getopts "su:h" opts; do
		case $opts in
			"s")
				r_is_running_setup=true
				;;
			"u")
				r_is_running_setup=true
				r_ssh_default_username="$OPTARG"
				;;
			"h")
				_usage
				exit 0
				;;
			"?")
				echo "Unknown option $OPTARG"
				_usage
				exit 1
				;;
			":")
				echo "No argument value for option $OPTARG"
				_usage
				exit 1
				;;
			*)
				# Should not occur
				echo "Unknown error while processing options"
				exit 1
				;;
		esac
	done
	
	if $r_is_running_setup; then
		_setup "$r_ssh_default_username"
		exit $?
	fi
fi
