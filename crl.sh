#!/bin/bash -e

print_help() {
cat <<EOF
crl.sh

Usage:
  crl.sh -s url_1 [-s url_2...] [-k] -t output
  crl.sh -h

Options:
  -h            Show this screen.
  -i            Interval to sleep in seconds (default 60, env CRL_INTERVAL)
  -k            Do not verify server ssl certs (curl -k, env CRL_VERIFY).
  -l            Header to check for modification (default Last-Modified, env CRL_HEADER).
  -m            Temp directory (default /tmp/crl.temp, env CRL_TMP).
  -p            Nginx PID location (default /run/nginx.pid, env CRL_NGINX_PID)
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
CRL_SIGNAL=${CRL-SIGNAL:-'HUP'}

/bin/mkdir -p ${CRL_TMP}
trap "rm -f ${CRL_TMP}/*; exit 0" SIGINT SIGTERM

sources=()
headers=()
curl_insecure=''

for src in ${CRL_SOURCES}; do
  sources=("${sources[@]}" "${src}") 
done

while getopts ':hi:kl:m:p:r:s:t:' opt; do
    case "${opt}" in
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
        header="$(curl -sI ${curl_insecure} ${sources[i]} | grep -i ${CRL_HEADER})" || echo "Failed to get CRL header ${CRL_HEADER} - ${sources[i]}"

        # If it differs, download the file
        if [[ -n "${header}" && "${headers[i]}" != "${header}" ]]; then
          echo "Downloading CRL - ${sources[i]}"
          curl -s ${curl_insecure} "${sources[i]}" -o "${CRL_TMP}/${i}.pem"
          if [[ $? -eq '0' ]]; then
            headers[i]="${header}"
            changed=1
          else
            echo "Failed to download CRL - ${sources[i]}"
          fi
        fi

    done

    # Regenerate the crl file if anything changed
    [[ "${changed}" -eq "1" ]] && cat "${CRL_TMP}"/*.pem > "${CRL_TARGET}" && echo "Updating target - ${CRL_TARGET}"
    
    # Reload nginx if we have pid file
    [[ -f "${CRL_NGINX_PID}" ]] && kill "-${CRL_SIGNAL}" $(cat "${CRL_NGINX_PID}") && echo "Sending ${CRL_SIGNAL} to pid $(cat ${CRL_NGINX_PID})"

    echo "Sleeping for ${CRL_INTERVAL}" && sleep "${CRL_INTERVAL}"
done