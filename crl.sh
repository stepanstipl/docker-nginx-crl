#!/bin/bash

[[ "$DEBUG" == 'true' ]] && set -x

log() {
  echo "$(date -u +${CRL_DATE_FORMAT}) ${@}"
}

log_d() {
  [[ "${DEBUG}" == 'true' ]] && log "${@}"
}

print_help() {
cat <<EOF
crl.sh

Usage:
  crl.sh -s url_1 [-s url_2...] [-k] -t output
  crl.sh -h

Options:
  -d            Date format passed to date command (default '%Y-%m-%dT%H:%M:%SZ', end CRL_DATE_FORMAT)
  -h            Show this screen.
  -i            Interval to sleep in seconds (default 60, env CRL_INTERVAL)
  -k            Do not verify server ssl certs (curl -k, env CRL_VERIFY).
  -l            Header to check for modification (default Last-Modified, env CRL_HEADER).
  -m            Temp directory (default /tmp/crl.temp, env CRL_TMP).
  -p            Nginx PID location (default /run/nginx.pid, env CRL_NGINX_PID)
  -q            Grep expression to use when searching for process, if PID location is not specififed (default 'nginx: master', env CRL_PGREP)
  -r            Signal to send to process on reload (default HUP, env CRL_SIGNAL) 
  -s            Source url (required, env CRL_SOURCES).
  -t            Target file (required, env CRL_TARGET).
EOF
}

CRL_INTERVAL=${CRL_INTERVAL:-'60'}
CRL_TMP=${CRL_TMP:-'/tmp/crl.temp'}
CRL_HEADER=${CRL_HEADER:-'Last-Modified'}
CRL_NGINX_PID=${CRL_NGINX_PID:-'/run/nginx.pid'}
CRL_SOURCES=${CRL_SOURCES:-''}
CRL_TARGET=${CRL_TARGET:-''}
CRL_VERIFY=${CRL_VERIFY:-'true'}
CRL_SIGNAL=${CRL_SIGNAL:-'HUP'}
CRL_DATE_FORMAT=${CRL_DATE_FORMAT:-'%Y-%m-%dT%H:%M:%SZ'}
CRL_PGREP=${CRL_PGREP:-'nginx: master'}

/bin/mkdir -p ${CRL_TMP}
trap "rm -f ${CRL_TMP}/*; exit 0" SIGINT SIGTERM SIGKILL EXIT

sources=()
headers=()
curl_insecure=''

for src in ${CRL_SOURCES}; do
  sources=("${sources[@]}" "${src}") 
done

while getopts ':d:hi:kl:m:p:r:s:t:' opt; do
    case "${opt}" in
    d)
        CRL_DATE_FORMAT="${OPTARG}"
        ;;
    h)
        print_help
        exit 0
        ;;
    i)
        CRL_INTERVAL="${OPTARG}"
        ;;
    k)
        CRL_VERIFY='false'
        ;;
    l)
        CRL_HEADER="${OPTARG}"
        ;;
    m)
        CRL_TMP="${OPTARG}"
        ;;
    p)
        CRL_NGIN_PID="${OPTARG}"
        ;;
    r)
        CRL_SIGNAL="${OPTARG}"
        ;;
    s)
        sources=("${sources[@]}" "${OPTARG}") 
        ;;
    t)
        CRL_TARGET="${OPTARG}"
        ;;
    \?)  echo "ERROR: Invalid option -${OPTARG}"
        exit 1
        ;;
    :)
        echo "ERROR: Option -$OPTARG requires an argument." >&2
        exit 1
        ;;
    esac
done

# Check we have target
[[ -z "${CRL_TARGET}" ]] && echo "ERROR: -t target is mandatory argument" && exit 1

# Check we have at least one CRL
sources_len="${#sources[@]}"
[[ "${sources_len}" -lt 1 ]] && echo "ERROR: at least one source url must be specified via -s argument" && exit 1

# Set options for insecure if requested
[[ "${CRL_VERIFY}" == 'false' ]] && curl_insecure='-k'

# Infinite loop
while true; do
    changed=0

    # Go through the list of provided sources
    for (( i=0; i<"${sources_len}"; i++ )); do

        # Check given header
        header=''
        header="$(curl -sI ${curl_insecure} ${sources[i]} | grep -i ${CRL_HEADER})" || log "Failed to get CRL header ${CRL_HEADER} - ${sources[i]}"

        # If it differs, download the file
        if [[ -n "${header}" && "${headers[i]}" != "${header}" ]]; then
          log "Downloading CRL - ${sources[i]}"
          curl -s ${curl_insecure} "${sources[i]}" -o "${CRL_TMP}/${i}.pem"
          if [[ $? -eq '0' ]]; then
            headers[i]="${header}"
            changed=1
          else
            log "Failed to download CRL - ${sources[i]}"
          fi
        fi

    done

    # Regenerate the crl file if anything changed
    if [[ "${changed}" -eq "1" ]]; then
      cat "${CRL_TMP}"/*.pem > "${CRL_TARGET}" && log "Updating target - ${CRL_TARGET}"
    
      # Reload nginx if we have pid file
      if [[ -f "${CRL_NGINX_PID}" ]]; then
        log "Sending ${CRL_SIGNAL} to pid $(cat ${CRL_NGINX_PID})" && kill "-${CRL_SIGNAL}" $(cat "${CRL_NGINX_PID}")
      elif [[ -n "${CRL_PGREP}" ]]; then
        pid=$(pgrep -f "${CRL_PGREP}") && log "Sending ${CRL_SIGNAL} to pid ${pid}" && kill "-${CRL_SIGNAL}" "${pid}"
      fi
    fi

    log_d "Sleeping for ${CRL_INTERVAL}"
    sleep "${CRL_INTERVAL}"
done
