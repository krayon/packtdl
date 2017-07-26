#!/bin/bash
# vim:set ts=4 sw=4 tw=80 et cindent ai si cino=(0,ml,\:0:
# ( settings from: http://datapax.com.au/code_conventions/ )
#
#/**********************************************************************
#    Packt DL
#    Copyright (C) 2017 Todd Harbour
#
#    This program is free software; you can redistribute it and/or
#    modify it under the terms of the GNU General Public License
#    version 2 ONLY, as published by the Free Software Foundation.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program, in the file COPYING or COPYING.txt; if
#    not, see http://www.gnu.org/licenses/ , or write to:
#      The Free Software Foundation, Inc.,
#      51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
# **********************************************************************/

# packtdl
#--------
# Packt Publishing library manager/downloader

# Config paths
_ETC_CONF="/etc/packtdl.conf"
_HOME_CONF="${HOME}/.packtdlrc"



############### STOP ###############
#
# Do NOT edit the CONFIGURATION below. Instead generate the default
# configuration file in your home directory thusly:
#
#     ./packtdl.bash -C >~/.packtdlrc
#
####################################

# [ CONFIG_START

# Packt DL Default Configuration
# ==============================

# DEBUG
#   This defines debug mode which will output verbose info to stderr
#   or, if configured, the debug file ( ERROR_LOG ).
DEBUG=0

# ERROR_LOG
#   The file to output errors and debug statements (when DEBUG !=
#   0) instead of stderr.
#ERROR_LOG="/tmp/packtdl.log"

# DOWNLOAD_DIR
#   The directory to download the ebooks to
DOWNLOAD_DIR="${HOME}/Downloads/"

# DIR_PER_BOOK
#   Specifies if each book should have it's own directory under DOWNLOAD_DIR. If
#   this is true (1), the directory will be named after the book title.
DIR_PER_BOOK=0

# CLAIM_EBOOKS
#   If packtdl should log in and try to claim the ebooks. NOTE: If this is
#   false (0), ebooks will not be downloaded (USER_ID, PASSWORD and
#   DOWNLOAD_FORMATS is ignored).
CLAIM_EBOOKS=1

# DOWNLOAD_FORMATS
#   An array of formats you want to download. Uses the format:
#     DOWNLOAD_FORMATS=(format1 format2 format3)
#   Obviously only formats that are available for download are valid. Currently
#   Packt appears to offer pdf, mobi and epub. You can also specify the special
#   format 'code' if you want to download the associated code for the book.
DOWNLOAD_FORMATS=(
    'epub'
    'pdf'
    'mobi'
    'code'
)

# USER_ID
#   Your user ID for the Packt Publishing website. This is most
#   likely the email address you used to register on their
#   website.
USER_ID="your.email@example.com"

# PASSWORD
#   Your password for the Packt Publishing website.
PASSWORD="your.password.here"

# TIME_SLEEP
#   The amount of time (in seconds) to sleep between requests
TIME_SLEEP=1

# TIMEOUT
#   The amount of time (in seconds) to wait for an entire web transaction
TIMEOUT=30

# DLTIMEOUT
#   The amount of time (in seconds) to wait for downloading of files. Keep in
#   mind that if you're downloading code, this may need to be set considerably
#   large. If a timeout does occur, packtdl will try to resume the download
#   when run again.
DLTIMEOUT=600

# RETRIES
#   The number of retries before giving up
RETRIES=5

# USER_AGENT
#   The user agent to use for downloading
USER_AGENT="Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:51.0) Gecko/20100101 Firefox/51.0"

# ] CONFIG_END

###
# Config loading
###
[ ! -z "${_ETC_CONF}"  ] && [ -r "${_ETC_CONF}"  ] && . "${_ETC_CONF}"
[ ! -z "${_HOME_CONF}" ] && [ -r "${_HOME_CONF}" ] && . "${_HOME_CONF}"

# Version
APP_NAME="Packt DL"
APP_VER="0.04"
APP_URL="http://gitlab.com/krayon/packtdl/"

# Program name
PROG="$(basename "${0}")"

# exit condition constants
ERR_NONE=0
ERR_MISSINGDEP=1
ERR_UNKNOWNOPT=2
ERR_INVALIDOPT=3
ERR_MISSINGPARAM=4
ERR_FILESYSWRITE=5
ERR_BADFORM=6
ERR_LOGIN=7
ERR_FREEBOOK=8

# Defaults not in config

baseurl="https://www.packtpub.com"
mybookspath="account/my-ebooks"
offerpath="packt/offers/free-learning"
dlpath="ebook_download"
dlpathc="code_download"
host="${baseurl#*/}"; host="${host#*/}"; host="${host#*/}"

emailfield="email"
passfield="password"

cookie_file=""
form_fields=""



# Params:
#   NONE
function show_version() {
    echo -e "\
${APP_NAME} v${APP_VER}\n\
${APP_URL}\n\
"
}

# Params:
#   NONE
function show_usage() {
    show_version
cat <<EOF

${APP_NAME} downloads the latest free book from Packt Publishing.

Usage: ${PROG} -h|--help
       ${PROG} -V|--version
       ${PROG} -C|--configuration
       ${PROG} [-v|--verbose] [-d|--bookdir]

-h|--help           - Displays this help
-V|--version        - Displays the program version
-C|--configuration  - Outputs the default configuration that can be placed in
                          ${_ETC_CONF}
                      or
                          ${_HOME_CONF}
                      for editing.
-v|--verbose        - Displays extra debugging information.  This is the same
                      as setting DEBUG=1 in your config.
-d|--bookdir        - Creates a separate directory per book. This is the same as
                      setting DIR_PER_BOOK=1 in your config.
Example: ${PROG}
EOF
}

function cleanup() {
    # Delete cookie file
    decho "Deleting cooking file: ${cookie_file}..."
    [ ! -z "${cookie_file}" ] && rm -f "${cookie_file}"

    cookie_file=""
}

function trapint() {
    echo "WARNING: Signal received: ${1}" >&2

    cleanup

    exit ${1}
}

# Output configuration file
function output_config() {
    cat "${0}"|\
         grep -A99999 '# \[ CONFIG_START'\
        |grep -v      '# \[ CONFIG_START'\
        |grep -B99999 '# \] CONFIG_END'  \
        |grep -v      '# \] CONFIG_END'  \
    #
}

# Debug echo
function decho() {
    # Not debugging, get out of here then
    [ ${DEBUG} -le 0 ] && return

    while read -r line; do #{
        echo "[$(date +'%Y-%m-%d %H:%M')] DEBUG: ${line}" >&2
    done< <(echo "${@}")
}

function get_form_fields() {
    # Get form fields and their default values
    formdata="$(\
        curl\
            --header         'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'\
            --header         'Accept-Language: en-US,en;q=0.5'\
            --header         'Accept-Encoding: gzip, deflate'\
            --silent\
            --location\
            --retry          "${RETRIES}"\
            --max-time       "${TIMEOUT}"\
            --user-agent     "${USER_AGENT}"\
            --cookie-jar     "${cookie_file}"\
            "${baseurl}"\
        |tr -d '\r'\
        |grep     -A99999 '<form .*packt-user-login-form'\
        |grep -m1 -B99999 '</form'\
        |sed 's#<#\n<#g'\
        |sed\
            -n\
            -e '/<input/s/^.*name="\([^"]*\)".*value="\([^"]*\)".*$/\1=\2/gp'\
            -e '/<input/s/^.*name="\([^"]*\)".*$/\1=/gp'\
    )"

    [ $(echo "${formdata}"|egrep "${emailfield}=|${passfield}="|wc -l) -lt 2 ] && {
        echo "ERROR: Form doesn't contain expected fields ${emailfield} and ${passfield}" >&2

        decho "FORM DATA:"
        decho "${formdata}"

        return 1
    }

    echo "${formdata}"|egrep -v "${emailfield}=|${passfield}="
    return 0
}

# Retrieve the "my books" page of your account
function get_mybooks_page() {
    pagedata="$(\
        curl\
            --header         'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'\
            --header         'Accept-Language: en-US,en;q=0.5'\
            --header         'Accept-Encoding: gzip, deflate'\
            --silent\
            --location\
            --retry          "${RETRIES}"\
            --max-time       "${TIMEOUT}"\
            --user-agent     "${USER_AGENT}"\
            --cookie         "${cookie_file}"\
            --cookie-jar     "${cookie_file}"\
            --header         'Connection: keep-alive'\
            "${baseurl}/${mybookspath}"\
        |tr -d '\r'\
    )" || {
        # FIXME: Be more descriptive?
        echo "ERROR: Curl returned: $?" >&2
        return 1
    }

    echo "${pagedata}"
}

# <url> <outfile>
function download_file() {
    url="${1}"
    out="${2}"

    # FIXME: Due to curl bug 1163 ( https://github.com/curl/curl/issues/1163 ),
    # we currently have to use '--fail' as a workaround. This means we cannot
    # (easily) tell the difference between a file that is already completely
    # downloaded, or some other error.
    curl\
        --header         'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'\
        --header         'Accept-Language: en-US,en;q=0.5'\
        --header         'Accept-Encoding: gzip, deflate'\
        --silent\
        --location\
        --retry          "${RETRIES}"\
        --max-time       "${DLTIMEOUT}"\
        --user-agent     "${USER_AGENT}"\
        --cookie         "${cookie_file}"\
        --cookie-jar     "${cookie_file}"\
        --continue-at    -\
        --output         "${out}"\
        --fail\
        "${url}"

    return $?
}

# <id> <name>
function dl_code() {
    book_dir="${DOWNLOAD_DIR}"

    # Here we create the directory to store the book
    # and code samples if it doesn't exist already.
    # This directory takes the name of the book title
    [ ! "${DIR_PER_BOOK}" -eq 0 ] && book_dir="${book_dir}/${2}"
    [ ! -d "${book_dir}" ] && mkdir -p "${book_dir}" || {
        echo "ERROR: Failed to create book directory: ${book_dir}" >&2
        exit ${ERR_FILESYSWRITE}
    }

    # FIXME: Currently always assuming ZIP
    out="${book_dir}/${2}.${1}.CODE.zip"
    
    # Get the mybooks page...
    # then filter out JUST the book we're interested in...
    # then get the code download link
    url="${baseurl}/$(get_mybooks_page\
    |grep -A999999     '<div class="product-line.*nid="'"${1}"'"'\
    |grep -B999999 -m2 '<div class="product-line'\
    |sed -n 's#.*href="\('"/${dlpathc}/"'[^"]*\)".*#\1#p'\
    )"

    download_file "${url}" "${out}"
    return $?
}

# <id> <format> <name>
function dl_book() {
    # Special case for code
    [ "${2}" == "code" ] && {
        dl_code "${1}" "${3}"
        return $?
    }

    book_dir="${DOWNLOAD_DIR}"

    # Here we create the directory to store the book
    # and code samples if it doesn't exist already.
    # This directory takes the name of the book title
    [ ! "${DIR_PER_BOOK}" -eq 0 ] && book_dir="${book_dir}/${3}"
    [ ! -d "${book_dir}" ] && mkdir -p "${book_dir}" || {
        echo "ERROR: Failed to create book directory: ${book_dir}" >&2
        exit ${ERR_FILESYSWRITE}
    }

    url="${baseurl}/${dlpath}/${1}/${2}"
    out="${book_dir}/${3}.${1}.${2}"

    download_file "${url}" "${out}"
    return $?
}

function login() {
    # Log in
    echo "Logging in..."
    pagedata="$(\
        curl\
            --header         'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'\
            --header         'Accept-Language: en-US,en;q=0.5'\
            --header         'Accept-Encoding: gzip, deflate'\
            --silent\
            --location\
            --retry          "${RETRIES}"\
            --max-time       "${TIMEOUT}"\
            --user-agent     "${USER_AGENT}"\
            --cookie         "${cookie_file}"\
            --cookie-jar     "${cookie_file}"\
            --data-urlencode "email=${USER_ID}"\
            --data-urlencode "password=${PASSWORD}"\
            ${form_fields}\
            "${baseurl}"\
        |tr -d '\r'\
    )" || {
        # FIXME: Be more descriptive?
        echo "ERROR: Curl returned: $?" >&2
        return 1
    }

    echo "${pagedata}"\
    |grep -m1 'edit-packt-user-login-form-form-token' &>/dev/null || {
        echo "ERROR: Failed to login, check username and password" >&2
        return 1
    }

    # Logged in

    decho "Logged in"
    return 0
}

# <claim_path>
function claim_book() {
    # Claim ebook and get d/l link
    echo "Claiming book..."
    pagedata="$(\
        curl\
            --header         'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'\
            --header         'Accept-Language: en-US,en;q=0.5'\
            --header         'Accept-Encoding: gzip, deflate'\
            --silent\
            --location\
            --retry          "${RETRIES}"\
            --max-time       "${TIMEOUT}"\
            --user-agent     "${USER_AGENT}"\
            --cookie         "${cookie_file}"\
            --cookie-jar     "${cookie_file}"\
            --header         'Connection: keep-alive'\
            --header         "Referer: ${baseurl}/${offerpath}"\
            "${baseurl}/${1}"\
        |tr -d '\r'\
    )" || {
        # FIXME: Be more descriptive?
        echo "ERROR: Curl returned: $?" >&2
        return 1
    }

    decho "Book claimed."
    return 0
}



# START #

# If debug file, redirect stderr out to it
[ ! -z "${ERROR_LOG}" ] && exec 2>>"${ERROR_LOG}"



# SIGINT  =  2 # (CTRL-c etc)
# SIGKILL =  9
# SIGUSR1 = 10
# SIGUSR2 = 12
for sig in 2 9 10 12; do #{
    trap "trapint ${sig}" ${sig}
done #}



decho "START"

# Check for required commands

# Process params
moreparams=1
decho "Processing ${#} params..."
while [ ${#} -gt 0 ]; do #{
    decho "Command line param: ${1}"

    [ ${moreparams} -gt 0 ] && {
        case "${1}" in #{
            # Verbose mode # [-v|--verbose]
            -v|--verbose)
                decho "Verbose mode specified"

                DEBUG=1

                shift 1; continue
            ;;

            # Help # -h|--help
            -h|--help)
                decho "Help"

                show_usage
                exit ${ERR_NONE}
            ;;

            # Version # -V|--version
            -V|--version)
                decho "Version"

                show_version
                exit ${ERR_NONE}
            ;;

            # Configuration output # -C|--configuration
            -C|--configuration)
                decho "Configuration"

                output_config
                exit ${ERR_NONE}
            ;;

            # Directory per book # -d|--bookdir
            -d|--bookdir)
                decho "Book Dir"

                DIR_PER_BOOK=1

                shift 1; continue
            ;;

            *)
                moreparams=0
                continue
            ;;

        esac #}
    }

    [ ${#} -gt 0 ] && {
        # Assume a parameter
        echo "ERROR: Unrecognised parameter ${1}..." >&2
        exit ${ERR_UNKNOWNOPT}
    }

done #}



# Create cookie file
cookie_file="$(mktemp --tmpdir -q "${PROG}.XXXXXX")" || {
    echo "ERROR: Failed to create cookie file" >&2
    exit ${ERR_FILESYSWRITE}
}
decho "Created cookie file: ${cookie_file}"

[ "${CLAIM_EBOOKS}" -eq 1 ] && {
    # Get the form fields
    decho "Getting form fields..."
    form_fields="$(get_form_fields)" || {
        exit ${ERR_BADFORM}
    }

    decho "FORM DATA:"
    decho "${form_fields}"

    # Format form data into curl '-d' parameters
    form_fields="$(echo "${form_fields}"|sed 's#^# -d #g'|tr -d '\n')"

    sleep "${TIME_SLEEP}"

    # On success, the page returned is similar, with a few exceptions:
    #   * The JavaScript Packt.user array will contain extra fields such as uid,
    #     name etc
    #   * The forms will have an input called "form_token" with a value of
    #     "edit-packt-user-login-form-form-token"
    #
    # Since we're not parsing script HEAD tags and so on, it's probably safer to
    # look for the form field instead of the Packt.user, despite that being "nicer"

    # Log in
    login || exit ${ERR_LOGIN}

    sleep "${TIME_SLEEP}"
}

# Get free book page
echo "Looking up free book..."
pagedata="$(\
    curl\
        --header         'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'\
        --header         'Accept-Language: en-US,en;q=0.5'\
        --header         'Accept-Encoding: gzip, deflate'\
        --silent\
        --location\
        --retry          "${RETRIES}"\
        --max-time       "${TIMEOUT}"\
        --user-agent     "${USER_AGENT}"\
        --cookie         "${cookie_file}"\
        --cookie-jar     "${cookie_file}"\
        "${baseurl}/${offerpath}"\
    |tr -d '\r'\
)" || {
    # FIXME: Be more descriptive?
    echo "ERROR: Curl returned: $?" >&2
    exit ${ERR_FREEBOOK}
}

# Get free book title
booktitle="$(\
    echo "${pagedata}"\
    |grep -A5 -m1 dotd-title\
    |sed -n 's#\t# #g;s#<[^>]*>##g;s#^ *##g;s# *$##g;/^[a-zA-Z0-9]/p'\
)"
[ "${booktitle}" == "" ] && {
    echo "ERROR: Failed to get free book title, try again later" >&2
    exit ${ERR_FREEBOOK}
}

sleep "${TIME_SLEEP}"

echo "Free book: ${booktitle}..."

[ "${CLAIM_EBOOKS}" -eq 1 ] && {
    # Get free book claim link
    claimpath="$(\
        echo "${pagedata}"\
        |grep -m1 'href=".*claim'\
        |sed 's#.*href="\([^"]*\)".*$#\1#'\
    )"
    [ "${claimpath}" == "" ] && {
        echo "ERROR: Failed to get free book claim path, try again later" >&2
        exit ${ERR_FREEBOOK}
    }
    decho "claimpath: ${claimpath}"

    # Claim ebook
    claim_book "${claimpath}"

    bookid="${claimpath%/*}"; bookid="${bookid##*/}"
    decho "bookid: ${bookid}"

    for fmt in "${DOWNLOAD_FORMATS[@]}"; do #{
        echo "Download format: ${fmt}..."
        dl_book ${bookid} "${fmt}" "${booktitle}" || {
            echo "WARNING: Downloading of format ${fmt} (partially?) failed" >&2
            echo "NOTE: This could just mean the file is completely"\
                 "downloaded already (due to curl bug)" >&2
        }
    done #}
}

cleanup

decho "DONE"

exit $?
