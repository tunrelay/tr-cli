#!/bin/bash

logLevelDebug=0
logLevelInfo=1
logLevelWarn=2
logLevelError=3
logLevel=${logLevelInfo}

version=0.0.1

showUsage() {
    local usage=""
    usage="${usage}Usage: $0 [OPTION]...\n"
    usage="${usage} -k, --apikey <key>          Provide API key [requied]\n"
    usage="${usage} -i, --init                  Initialize device.\n"
    usage="${usage}                             Mutually exclussive with --config.\n"
    usage="${usage}     --name <name>           (Optional) Device name. Only used with --init.\n"
    usage="${usage} -c, --config                Prepare config file for network connection.\n"
    usage="${usage}                             Mutually exclussive with --init.\n"
    usage="${usage}     --netuuid <uuid>        (Optional) Network UUID. Only used with --config.\n"
    usage="${usage}                             Only used with --config.\n"
    usage="${usage} -u, --up, --connect         Bring up network connection.\n"
    usage="${usage}     --netstart              (Optional) Start network if not running.\n"
    usage="${usage}                             Only used with --connect.\n"
    usage="${usage} -d, --down, --disconnect    Bring down network connection.\n"
    usage="${usage}     --iface <iface-name>    (Optional) Custom name for WG interface.\n"
    usage="${usage}                             Can be used with --config, --up, --down.\n"
    usage="${usage} -q, --quicksetup            One command complete setup for a new device\n"
    usage="${usage} -h, --help                  Display this help and exit.\n"
    # usage="${usage} -v, --verbose               Make the operation more talkative.\n"
    usage="${usage} -V, --version               Show version number and quit.\n"
    echo -en "${usage}"
}

init=0
config=0
netUuid=""
netStart=0
ifaceName=""
operation=""
while [ $# -gt 0 ]; do
    case $1 in
        -V|--version)
            echo "tunrelay CLI ${version}"
            exit
            ;;
        -h|--help)
            showUsage
            exit
            ;;
        -k|--apikey)
            apiKey="$2"
            [ "${apiKey%-*}" = "-" ] && {
                echo "ERR" && exit
            }
            shift # past value
            ;;
        -i|--init)
            init=1
            ;;
        --name)
            deviceName="$2"
            [ -z "${deviceName}" ] && {
                echo "ERR" && exit
            }
            [ "${deviceName%-*}" = "-" ] && {
                echo "ERR" && exit
            }
            shift # past value
            ;;
        -c|--config)
            config=1
            ;;
        --netuuid)
            netUuid="$2"
            [ -z "${netUuid}" ] && {
                echo "ERR" && exit
            }
            [ "${netUuid%-*}" = "-" ] && {
                echo "ERR" && exit
            }
            shift # past value
            ;;
        --iface)
            ifaceName="$2"
            [ -z "${ifaceName}" ] && {
                echo "ERR" && exit
            }
            [ "${ifaceName%-*}" = "-" ] && {
                echo "ERR" && exit
            }
            shift # past value
            ;;
        --netstart)
            netStart=1
            ;;
        -u|--up|--connect)
            operation="up"
            ;;
        -d|--down|--disconnect)
            operation="down"
            ;;
        -q|--quicksetup)
            operation="quicksetup"
            ;;
        -*|--*)
            echo "Unknown option $1"
            exit 1
            ;;
    esac
    shift # past argument
done

[ ${logLevel} -eq ${logLevelDebug} ] && {
    echo "apiKey     = ${apiKey}"
    echo "init       = ${init}"
    echo "deviceName = ${deviceName}"
    echo "config     = ${config}"
    echo "netUuid    = ${netUuid}"
    echo "netStart   = ${netStart}"
    echo "operation  = ${operation}"
}

isUint() { case $1 in '' | *[!0-9]* ) return 1;; esac; }
isAlphaNumeric() { case $1 in '' | *[!A-Za-z0-9]* ) return 1;; esac; }

showErrorAndQuit() {
    local msg=$1
    shift
    [ -z "${msg}" ] && echo "[${FUNCNAME[0]}]: msg is required as arg1." && exit 2
    echo "[ERR]: ${msg}"
    showUsage
    exit 1
}

tempDir=$(mktemp -p /tmp -d tr-cli-XXXXXX)

cleanup() { rm -rf ${tempDir}; [ ${logLevel} -eq ${logLevelDebug} ] && { echo "cleanup $1"; }; trap - EXIT; exit; }

for sig in EXIT QUIT INT TERM; do trap "cleanup ${sig}" ${sig}; done

trApiRequest() {
    local type=$1
    shift
    [ -z "${type}" ] && echo "[${FUNCNAME[0]}]: type is required as arg1." && return 2
    type=${type^^}
    case "${type}" in
        "GET") ;;
        "POST") ;;
        "PATCH") ;;
        "DELETE") ;;
        *) echo "[${FUNCNAME[0]}]: type '${type}' is not supported." && return 2
    esac

    local path=$1
    shift
    [ -z "${path}" ] && echo "[${FUNCNAME[0]}]: path is required as arg2." && return 2

    local data=$1
    shift
    case "${type}" in
        "POST") [ -z "${data}" ] && echo "[${FUNCNAME[0]}]: data is required as arg3." && return 2;;
        "PATCH") [ -z "${data}" ] && echo "[${FUNCNAME[0]}]: data is required as arg3." && return 2;;
    esac

    local trApiKey="${apiKey}"
    [ -z "${trApiKey}" ] && echo "[${FUNCNAME[0]}]: api key cannot be empty." && return 2

    local trApiUrl="https://tunrelay.com/api/v1"

    local responseFile=$(mktemp -p ${tempDir} response-XXXXXX.json)
    local responseCode=""
    case "${type}" in
        "POST") responseCode="$(curl -sX ${type^^} -w '%{http_code}' -o ${responseFile} -H "Authorization: Bearer ${trApiKey}" -H "Content-Type: application/json" -d "${data}" "${trApiUrl}${path}")";;
        "PATCH") responseCode="$(curl -sX ${type^^} -w '%{http_code}' -o ${responseFile} -H "Authorization: Bearer ${trApiKey}" -H "Content-Type: application/json" -d "${data}" "${trApiUrl}${path}")";;
        *) responseCode="$(curl -sX ${type^^} -w '%{http_code}' -o ${responseFile} -H "Authorization: Bearer ${trApiKey}" -H "Content-Type: application/json" "${trApiUrl}${path}")";;
    esac
    local returnCode=1
    case "${responseCode}" in
        "200")
            cat ${responseFile}
            rm ${responseFile}
            returnCode=0
            ;;
        *)
            echo "${responseCode} ${responseFile}"
            returnCode=1
            ;;
    esac
    return ${returnCode}
}

validateApiKey() {
    [ -z "${apiKey}" ] && showErrorAndQuit "--apikey argument is required"
    [ ${#apiKey} -lt 32 ] && showErrorAndQuit "Invalid API key (too short)"
    ! isAlphaNumeric "${apiKey}" && showErrorAndQuit "Invalid API key (contains invalid characters)"
    # check the API key with a request as well
    trApiRequest get /whoami &>/dev/null || showErrorAndQuit "Invalid API Key (does not exist)"
}
validateApiKey

# [ "${init}" -eq 0 -a "${config}" -eq 0 ] && showErrorAndQuit "--init or --config argument is required"

# log() {
#     # Check for minimum 2 arguments
#     if [ $# -lt 2 ]; then
#         echo "Usage: ${FUNCNAME[0]} <level> <message>" && return 1
#     fi

#     local level=$1
#     shift 1
#     local message="$*"

#     # Check if both level and message are provided
#     if [ -z "${level}" ] || [ -z "${message}" ]; then
#         echo "Usage: log <level> <message>" && return 1
#     fi

#     local levelVal
#     case "${level}" in
#         dbg|DBG|debug  |DEBUG)      levelVal=${logLevelDebug}; level="DBG";;
#         inf|INF|info   |INFO)       levelVal=${logLevelInfo}; level="INF";;
#         wrn|WRN|warning|WARNING)    levelVal=${logLevelWarn}; level="WRN";;
#         err|ERR|error  |ERROR)      levelVal=${logLevelError}; level="ERR";;
#         *)                          echo "Usage: log <level> <message>" && return 1;;
#     esac

#     if [ ${levelVal} -ge ${logLevel} ]; then
#         local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
#         if [ ${levelVal} -eq ${logLevelError} ]; then
#             printf '[%s] [%s] %s\n' "${timestamp}" "${level}" "${message}" >&2
#         else
#             printf '[%s] [%s] %s\n' "${timestamp}" "${level}" "${message}"
#         fi
#     fi
# }
# log_debug() { log dbg "$*"; }
# log_info() { log inf "$*"; }
# log_warn() { log wrn "$*"; }
# log_error() { log err "$*"; }

# handleError() {
#     # Check for minimum 2 arguments
#     if [ $# -lt 3 ]; then
#         echo "Usage: ${FUNCNAME[0]} <exitCode> <errorMessage> <errorContext>" && return 1
#     fi

#     local exitCode=$1
#     local errorMessage=$2
#     shift 2
#     local errorContext="$*"

#     log_error "${errorMessage}"
#     if [ -n "${errorContext}" ]; then
#         log_error "Context: ${errorContext}"
#     fi

#     if [ ${logLevel} -eq ${logLevelDebug} ]; then
#         log_error "Stack trace:"
#         local frame=0
#         while caller $frame; do
#             (( frame++ ))
#         done
#     fi

#     # exit "${exitCode}"
#     return ${exitCode}
# }

# # trap 'handleError 1 "Unexpected error occurred" "Line: $LINENO"' ERR

# makeApiRequest() {
#     local method=$1
#     local endpoint=$2
#     local data=${3:-}
#     local response_file
#     local response_code

#     response_file=$(mktemp -p "${tempDir}" response-XXXXXX.json)

#     local trApiUrl="https://tunrelay.com/api/v1"

#     local curl_opts=(
#         -sX "${method}"
#         -w '%{http_code}'
#         -o "${response_file}"
#         -H "Authorization: Bearer ${apiKey}"
#         -H "Content-Type: application/json"
#         --connect-timeout 10
#         --max-time 30
#         --retry 3
#         --retry-delay 1
#     )

#     if [[ -n "${data}" ]]; then
#         curl_opts+=(-d "${data}")
#     fi

#     response_code=$(curl "${curl_opts[@]}" "${trApiUrl}${endpoint}")

#     case "${response_code}" in
#         200) cat "${response_file}"; rm "${response_file}"; return 0 ;;
#         401) handleError 1 "Unauthorized. Please check your API key" ;;
#         403) handleError 1 "Forbidden. You don't have permission to access this resource" ;;
#         404) handleError 1 "Resource not found" ;;
#         500) handleError 1 "Server error occurred" ;;
#         *) handleError 1 "Unexpected response code: ${response_code}" ;;
#     esac
# }

# TODO: check if curl and jq exist

# check if wireguard exists
checkIfWgExists() { command -v wg-quick &>/dev/null; }
checkIfWgExists || showErrorAndQuit "WireGuard must be installed first. Please install WireGuard, then run tunrelay CLI again."

# Default iface name
trWgIfaceName=tr-wg0
# Custom iface name
[ -n "${ifaceName}" ] && trWgIfaceName=${ifaceName}
trWgConfigFile=/etc/wireguard/${trWgIfaceName}.conf

trWgPrivateKeyFile="/etc/wireguard/tr-key.priv"
trWgPublicKeyFile="/etc/wireguard/tr-key.pub"

trWgPrivateKey=""
trWgPublicKey=""

# get or create wg key pair for this device
getWgKeys() {
    [ $(id -u) -ne 0 ] && showErrorAndQuit "Superuser access is required to read/modify WireGuard private/public keys. Exiting."
    trWgPrivateKey="$(cat ${trWgPrivateKeyFile} 2>/dev/null)"
    [ -z "${trWgPrivateKey}" ] && trWgPrivateKey=$(wg genkey | tee ${trWgPrivateKeyFile})
    trWgPublicKey="$(wg pubkey <<< ${trWgPrivateKey} | tee ${trWgPublicKeyFile})"
    chmod 600 ${trWgPrivateKeyFile} ${trWgPublicKeyFile}
}
getWgKeys

init() {

    clientUuids=$(trApiRequest get /client)
    [ $? -ne 0 ] && {
        echo ERROR 0x000001
        return
    }

    shouldCreateClient=1
    for clientUuid in $(jq -nr "${clientUuids} | .[]"); do
        clientInfo=$(trApiRequest get /client/${clientUuid})
        [ $? -ne 0 ] && {
            echo ERROR 0x000002
            continue
        }
        clientPublicKey="$(echo ${clientInfo} | jq -r '.public_key')"
        [ "${clientPublicKey}" = "${trWgPublicKey}" ] && {
            shouldCreateClient=0
            echo "Client for this device already exists."
            break
        }
    done

    [ ${shouldCreateClient} -ne 0 ] && {
        echo "Creating client for this device."
        if [ -n "${deviceName}" ]; then
            trApiRequest post /client "{\"name\":\"${deviceName}\",\"public_key\":\"${trWgPublicKey}\"}"
        else
            trApiRequest post /client "{\"name\":\"$(hostname)\",\"public_key\":\"${trWgPublicKey}\"}"
        fi
        [ $? -ne 0 ] && {
            echo ERROR 0x000003
            return
        }
    }
}
[ ${init} -eq 1 ] && { init; exit; }

config() {
    local netUuid=$1
    shift

    clientUuids=$(trApiRequest get /client)
    [ $? -ne 0 ] && {
        echo ERROR 0x000001
        return
    }

    thisDeviceClientUuid=""
    thisDeviceClientInfo=""
    for clientUuid in $(echo "${clientUuids}" | jq -r '.[]'); do
        clientInfo=$(trApiRequest get /client/${clientUuid})
        [ $? -ne 0 ] && {
            echo ERROR 0x000002
            continue
        }
        clientPublicKey="$(echo "${clientInfo}" | jq -r '.public_key')"
        [ "${clientPublicKey}" = "${trWgPublicKey}" ] && {
            thisDeviceClientUuid="${clientUuid}"
            thisDeviceClientInfo="${clientInfo}"
            break
        }
    done
    [ -z "${thisDeviceClientUuid}" ] && {
        echo ERROR 0x000003
        return
    }

    assignedNetworksCount="$(echo "${clientInfo}" | jq -r '.assigned_to_networks | length')"
    ! isUint "${assignedNetworksCount}" && {
        echo ERROR 0x000004
        return
    }
    [ ${assignedNetworksCount} -lt 1 ] && {
        echo ERROR 0x000004
        return
    }

    networkSelected=0
    assignedNetworkUuids="$(echo "${clientInfo}" | jq -r '.assigned_to_networks[]')"

    if [ -n "${netUuid}" ]; then
        for assignedNetworkUuid in ${assignedNetworkUuids}; do
            [ "${assignedNetworkUuid}" = "${netUuid}" ] && {
                networkSelected=1
                break
            }
        done
    else
        echo "Select network to prepare config for:"
        for ((i=0; i < ${assignedNetworksCount}; i++)); do
            assignedNetworkUuid="$(echo "${clientInfo}" | jq -r ".assigned_to_networks[${i}]")"

            assignedNetworkInfo=$(trApiRequest get /network/${assignedNetworkUuid})
            [ $? -ne 0 ] && {
                echo ERROR 0x000005
                return
            }
            assignedNetworkName=$(echo "${assignedNetworkInfo}" | jq -r '.name')
            echo "${i}) ${assignedNetworkName}"
        done

        while true; do
            echo "Enter number to select network:"
            read -r n
            ! isUint "${n}" && continue
            [ ${n} -lt 0 -o ${n} -ge ${assignedNetworksCount} ] && continue
            echo "Selected: ${n}"
            netUuid="$(echo "${clientInfo}" | jq -r ".assigned_to_networks[${n}]")"
            networkSelected=1
            break
        done
    fi
    [ ${networkSelected} -eq 0 ] && {
        echo ERROR 0x000006
        return
    }

    networkInfo=$(trApiRequest get /network/${netUuid})
    [ $? -ne 0 ] && {
        echo ERROR 0x000007
        return
    }
    networkStatus=$(echo "${networkInfo}" | jq -r '.status')

    # if [ "${networkStatus}" != "running" ]; then
    #     # if [ ${netStart} -ne 0 ]; then
    #     #     reqOutput=$(trApiRequest post /network/${netUuid}/start)
    #     #     [ $? -ne 0 ] && {
    #     #         echo ERROR 0x000008
    #     #         return
    #     #     }
    #     # else
    #         echo ERROR 0x000008
    #         return
    #     # fi
    # fi

    deviceConfigJson=$(trApiRequest get /config/${netUuid}/${thisDeviceClientUuid}/json)
    [ $? -ne 0 ] && {
        echo ERROR 0x000009
        return
    }

    echo "${deviceConfigJson}" | jq -r '.config' > ${trWgConfigFile}
    sed -i -e "s|^PrivateKey = .*$|PrivateKey = ${trWgPrivateKey}|" ${trWgConfigFile}

    # wg-quick up ${trWgIfaceName}

}
[ ${config} -eq 1 ] && { config ${netUuid}; exit; }

up() {
    [ $(id -u) -ne 0 ] && showErrorAndQuit "Superuser access is required to bring up WireGuard interface. Exiting."

    # Check if config file exists
    [ ! -s "${trWgConfigFile}" ] && showErrorAndQuit "Config file not found. Please run --config first."

    # Check if interface is already up
    wg show ${trWgIfaceName} &>/dev/null && {
        echo "Interface ${trWgIfaceName} is already up"
        return 0
    }

    # Bring up the interface
    wg-quick up ${trWgIfaceName}
    return $?
}
[ "${operation}" = "up" ] && { up; exit; }

down() {
    [ $(id -u) -ne 0 ] && showErrorAndQuit "Superuser access is required to bring down WireGuard interface. Exiting."

    # Check if interface exists
    ! wg show ${trWgIfaceName} &>/dev/null && {
        echo "Interface ${trWgIfaceName} is not up"
        return 0
    }

    # Bring down the interface
    wg-quick down ${trWgIfaceName}
    return $?
}
[ "${operation}" = "down" ] && { down; exit; }

quickSetup() {

    thisDeviceClientUuid=""
    quickSetupNetworkUuid=""

    clientUuids=$(trApiRequest get /client)
    [ $? -ne 0 ] && {
        echo ERROR 0x000001
        return 1
    }

    for clientUuid in $(jq -nr "${clientUuids} | .[]"); do
        clientInfo=$(trApiRequest get /client/${clientUuid})
        [ $? -ne 0 ] && {
            echo ERROR 0x000002
            continue
        }
        clientPublicKey="$(echo ${clientInfo} | jq -r '.public_key')"
        [ "${clientPublicKey}" = "${trWgPublicKey}" ] && {
            thisDeviceClientUuid=${clientUuid}
            break
        }
    done

    [ -z ${thisDeviceClientUuid} ] && {
        clientData="{\"name\":\"$(hostname)\",\"public_key\":\"${trWgPublicKey}\"}"
        clientResponse=$(trApiRequest post /client "${clientData}")
        [ $? -ne 0 ] && {
            echo ERROR 0x000003
            return 1
        } || {
            thisDeviceClientUuid="$(echo ${clientResponse} | jq -r '.uuid')"
        }
    }

    networkData="{\"name\":\"QuickSetup_$(date +"%Y-%m-%d_%H-%M-%S")\",\"subnet\":\"10.10.10.0/24\"}"

    networkResponse=$(trApiRequest post /network "${networkData}")
    [ $? -ne 0 ] && {
        echo ERROR 0x000004
        return 1
    } || {
        quickSetupNetworkUuid="$(echo ${networkResponse} | jq -r '.uuid')"
    }

    assignResponse=$(trApiRequest post "/network/${quickSetupNetworkUuid}/client/${thisDeviceClientUuid}" "{}")
    [ $? -ne 0 ] && {
        echo ERROR 0x000005
        return 1
    }

    startResponse=$(trApiRequest post "/network/${quickSetupNetworkUuid}/start" "{}")
    [ $? -ne 0 ] && {
        echo ERROR 0x000006
        return 1
    }

    timeout=60
    for ((i=0; i<timeout; i++)); do
        sleep 1
        networkInfo=$(trApiRequest get "/network/${quickSetupNetworkUuid}")
        # [ $? -ne 0 ] && {
        #     echo ERROR 0x000007
        #     return
        # }

        networkStatus=$(echo "${networkInfo}" | jq -r '.status')

        [ "${networkStatus}" = "running" ] && break
    done

    [ "${networkStatus}" != "running" ] && {
        echo ERROR 0x000007
        return 1
    }

    deviceConfigJson=$(trApiRequest get /config/${quickSetupNetworkUuid}/${thisDeviceClientUuid}/json)
    [ $? -ne 0 ] && {
        echo ERROR 0x000008
        return 1
    }

    echo "${deviceConfigJson}" | jq -r '.config' > ${trWgConfigFile}
    sed -i -e "s|^PrivateKey = .*$|PrivateKey = ${trWgPrivateKey}|" ${trWgConfigFile}

    wg-quick up ${trWgIfaceName}
    [ $? -ne 0 ] && {
        echo ERROR 0x000009
        return 1
    }

    return 0
}
[ "${operation}" = "quicksetup" ] && { quickSetup; exit; }

true
