#!/bin/bash
#set -ex

readonly cron_file="$1"; shift
readonly time_unit_limits="60 24 31 12 7"
readonly default_ifs="$IFS"


readonly red='\033[0;31m'
readonly cyan='\033[0;36m'
readonly yellow='\033[0;33m'
readonly green='\033[0;32m'
readonly no_color='\033[0m'

#####
#
# Messages block
#
#####

print_color(){
	local color="$1"; shift
	local line="$1"; shift

	echo -e "${!color}${line}${no_color}"
}

get_level_prefix(){
	local message_level="$1"; shift
	local color="$1"; shift

	local level_prefix=""
	local level_sep="  └─"
	local i
	for i in $(seq 1 $message_level); do
		level_prefix="${level_prefix}${level_sep}"
	done

	level_prefix="${no_color}${level_prefix}${!color}"

	echo -n "$level_prefix"
}

message(){
	local message_type="$1"; shift
	local text="$1"; shift	

	local message_level=1
	if [[ "${FUNCNAME[1]}" == "main" ]]; then
		message_level=0
	fi
	
	local color="green"
	local prefix="[INFO]"
	case "$message_type" in
		"err"|"error")
			color="red"
			prefix="[ERROR] "
			;;
		"warn"|"warning")
			color="yellow"
			prefix="[WARNING] "
			;;
		"debug")
			color="cyan"
			prefix="[DEBUG] "
			;;
		*)
			color="green"
			prefix="[INFO] "
			;;
	esac
	
	local level_prefix=$(get_level_prefix "$message_level" "$color")
	
	print_color "$color" "${level_prefix}${prefix}${text}"
}

#####
#
# Environment variables block
#
#####

is_environment(){
	local line="$1"; shift
	
	local result=1 
	if [[ "$line" =~ ^[A-Z]+= ]]; then
		result=0
	fi

	return "$result"
}

check_warn_environment(){
	#There you may place some checks against environment variables in your crontab.
	#There are you should place only warnings. Error checks you should place in check_err_environment()

	local line="$1"; shift


	local var=$(cut -f 1 -d "=" <<< $line)
	local value=$(cut -f 2 -d "=" <<< $line)

	#Check if SHELL=/bin/bash
	#if [[ "$var" == "SHELL" ]] && [[ "$value" != "/bin/bash" ]]; then
	#	message warn "SHELL variable is not /bin/bash: $shell. Please doublecheck if correct."
	#fi
}
check_err_environment(){
	#There you may place some checks against environment variables in your crontab.
	#There are you should place only errors. Warning checks you should place in check_warn_environment()

	local line="$1"; shift
	local result=0

	local var=$(cut -f 1 -d "=" <<< $line)
	local value=$(cut -f 2 -d "=" <<< $line)

	echo -n "$result"
}

#####
#
# Comment lines block
#
#####

is_comment_or_blank(){
	local line="$1"; shift
	
	local result=1
	if [[ "$line" =~ ^# ]] || [[ "$line" =~ ^$ ]]; then 
		local result=0
	fi

	return "$result"
}

check_warn_comment(){
	#There you may place some checks against comments in your crontab.
	#There are you should place only warnings. Error checks you should place in check_err_comment()

	local line="$1"; shift
}

check_err_comment(){
	#There you may place some checks against comments in your crontab.
	#There are you should place only errors. Warning checks you should place in check_warn_comment()

	local line="$1"; shift
	local result=0

	echo -n "$result"
}

#####
#
# Crontab lines block
#
#####

is_correct_unit_number(){
	local unit="$1"; shift
	local limit="$1"; shift
	
	local result=1
	if [[ "$unit" =~ ^[0-9]{1,2}$ ]] && [[ "$unit" -le "$limit" ]]; then
		result=0
	fi
	
	return "$result"
}

is_correct_unit(){
	local unit="$1"; shift
	local limit="$1"; shift

	local result=1

	#number
	if is_correct_unit_number "$unit" "$limit"; then
		result=0
	fi

	#globe
	if [[ "$unit" == "*" ]]; then
		result=0
	fi

	#regular globe
	if [[ "$unit" =~ ^\*/[0-9]{1,2}$ ]]; then
		result=0
	fi

	#interval
	if [[ "$unit" =~ ^[0-9]{1,2}-[0-9]{1,2}$ ]]; then
		local begin=$(cut -d "-" -f 1 <<< "$unit")
		local end=$(cut -d "-" -f 2 <<< "$unit")
		result=0
		if ! is_correct_unit_number "$begin" "$limit" || ! is_correct_unit_number "$end" "$limit"; then
			result=1
		fi
	fi
		
	#list
	if [[ "$unit" =~ , ]]; then
		result=0
		IFS=","
		local item
		for item in $unit; do
			if ! is_correct_unit "$item" "$limit"; then
				result=1
				message err "'$item' is not a correct list member in '$unit'"
				break
			fi
		done
		IFS="$default_ifs"
	fi

	return "$result"
}

is_crontab_line(){
	local line="$1"; shift

	local result=1
	if [[ "$line" =~ ^[0-9*,-\/]+ ]]; then
		result=0
	fi

	return "$result"
}

check_warn_crontab(){
	#There you may place some checks against crontab lines
	#There are you should place only warnings. Error checks you should place in check_err_crontab()
	local line="$1"; shift
	local severity="warning"

	local i
	for i in $(seq 1 5); do
		item=$(get_item "$line" "$i")
		limit=$(get_item "$time_unit_limits" "$i")
	
		#There you could place time unit warn checks
	done
	
	local name=$(get_item "$line" 6)
	#There you could place username warn checks

	local cmd=$(awk '{print substr($0, index($0,$7))}'<<< "$line")
	local executive=$(get_item "$cmd" "1")
	#There you could place command warn checks
	#check fo unescaped '%' symbol
	if [[ "$cmd" =~ % ]] && [[ "$cmd" =~ [^\\]% ]]; then
		message "$severity" "Command have not escaped percent(%) symbol: $cmd"
		result=1
	fi
}

check_err_crontab(){
	#There you may place some checks against crontab lines
	#There are you should place only errors. Error checks you should place in check_warn_crontab()
	local line="$1"; shift
	local severity="error"

	local result=0

	##### Time units block
	local i
	for i in $(seq 1 5); do
		item=$(get_item "$line" "$i")
		limit=$(get_item "$time_unit_limits" "$i")
		#There you could place time unit err checks
		if ! is_correct_unit "$item" "$limit"; then
			result=1
			message "$severity" "Wrong time item at $i position: '$item'"
			break
		fi
	done
	

	##### Username block
	local name=$(get_item "$line" 6)

	#There you could place username err checks
	#Common username check
	if ! [[ "$name" =~ ^[a-z_]([a-z0-9_-]{0,31}|[a-z0-9_-]{0,30}\$)$ ]]; then 
		result=1
		message "$severity" "Not a correct user name: '$name'"
	fi

	##### Command block
	local cmd=$(awk '{print substr($0, index($0,$7))}'<<< "$line")
	local executive=$(get_item "$cmd" "1")

	#There you could place command err checks


	echo -n "$result"
}

#####
#
# Main block
#
#####

get_item(){
	local list="$1"; shift
	local idx="$1"; shift

	result=$(awk -v i="$idx" '{print $i}' <<< "$list")

	echo "$result"
}

update_exit_result(){
	local exit_result=$1; shift
	local result=$1; shift

	if [[ $exit_result -eq 0 ]]; then
		exit_result=$result
	fi
	
	echo -n "$exit_result"
}

get_return_code(){
	local array=("$@"); shift
	
	return_code="${array[-1]}"

	echo -n "$return_code"
}

print_array(){
	local array=("$@"); shift

	local i
	for i in "${array[@]}" ; do 
		echo "$i"
	done
}

main(){
	local file="$1"; shift

	local exit_result=0
	local block_result=0
	local shell=""
	
	if ! [[ -f "$file" ]] || ! [[ -r "$file" ]]; then
		exit_result=1
		message err "Not such file or file is not readable: $file"
		return "$exit_result"
	fi

	while read -r line; do
		local -a err_output=()
		local -a warn_output=()

		#environment variable
		if is_environment "$line"; then
			readarray -t warn_output < <(check_warn_environment "$line")
			readarray -t err_output < <(check_err_environment "$line")

			block_result=$(get_return_code "${err_output[@]}")
			unset err_output[${#err_output[@]}-1]
			exit_result=$(update_exit_result "$exit_result" "$block_result" | tail -1)

			local prefix=""
			local severity="info"
			if [[ $block_result -eq 1 ]]; then  		
				local severity="error"
				local prefix="Not a correct environment variable: "
				message "$severity" "${prefix}${line}" 
				print_array "${err_output[@]}"
				print_array "${warn_output[@]}"
				echo
			fi
			
			continue
		fi

		#comment or blank 
		if is_comment_or_blank "$line"; then
			readarray -t warn_output < <(check_warn_comment "$line")
			readarray -t err_output < <(check_err_comment "$line")

			block_result=$(get_return_code "${err_output[@]}")
			unset err_output[${#err_output[@]}-1]
			exit_result=$(update_exit_result "$exit_result" "$block_result" | tail -1)

			local prefix=""
			local severity="info"
			if [[ $block_result -eq 1 ]]; then  		
				local severity="error"
				local prefix="Not a correct comment line: "
				message "$severity" "${prefix}${line}" 
				print_array "${err_output[@]}"
				print_array "${warn_output[@]}"
				echo
			fi
			
			continue
		fi

		#crontab line
		if is_crontab_line "$line"; then
			readarray -t warn_output < <(check_warn_crontab "$line")
			readarray -t err_output < <(check_err_crontab "$line")

			block_result=$(get_return_code "${err_output[@]}")
			unset err_output[${#err_output[@]}-1]
			exit_result=$(update_exit_result "$exit_result" "$block_result" | tail -1)

			local prefix=""
			local severity="info"
			if [[ $block_result -eq 1 ]]; then  		
				local severity="error"
				local prefix="Not a correct crontab line: "

			fi
			message "$severity" "${prefix}${line}" 
			print_array "${err_output[@]}"
			print_array "${warn_output[@]}"
			echo
	
			continue
		fi	
	
		exit_result=$(update_exit_result "$exit_result" "1" | tail -1)
		local severity="error"
		local prefix="Not a correct line: "
		message "$severity" "${prefix}${line}" 
		echo

	done < "$file"

	return "$exit_result"
}

main "$cron_file"
