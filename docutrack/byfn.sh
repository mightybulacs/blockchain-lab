export PATH=${PWD}/../bin:${PWD}:$PATH
export FABRIC_CFG_PATH=${PWD}


function networkUp() {
    if [ ! -d "crypto-config" ]; then
        generateCerts
        replacePrivateKey
        generateChannelArtifacts
    fi
    if [ "${IF_COUCHDB}" == "couchdb" ]; then
        CHANNEL_NAME=$CHANNEL_NAME TIMEOUT=$CLI_TIMEOUT DELAY=$CLI_DELAY docker-compose -f $COMPOSE_FILE -f $COMPOSE_FILE_COUCH up -d 2>&1
    else
        CHANNEL_NAME=$CHANNEL_NAME TIMEOUT=$CLI_TIMEOUT DELAY=$CLI_DELAY docker-compose -f $COMPOSE_FILE up -d 2>&1
    fi
    if [ $? -ne 0 ]; then
        echo "[error] unable to start network. exiting..."
        docker logs -f cli
        exit 1
    fi
    # docker logs -f cli
}


function networkDown() {
    if [ "${IF_COUCHDB}" == "couchdb" ]; then
        docker-compose -f $COMPOSE_FILE -f $COMPOSE_FILE_COUCH down
    fi
    docker-compose -f $COMPOSE_FILE down

    if [ "$MODE" != "restart" ]; then
        clearContainers
        clearImages
        rm -rf channel-artifacts/*.block channel-artifacts/*.tx crypto-config
        rm -f docker-compose-e2e.yaml
    fi
}


function clearContainers() {
    CONTAINER_IDS=$(docker ps -aq)
    if [ -z "$CONTAINER_IDS" -o "$CONTAINER_IDS" == " " ]; then
        echo "--- no container available for deletion ---"
    else
        docker rmi -f $CONTAINER_IDS
    fi
}


function clearImages() {
    DOCKER_IMAGE_IDS=$(docker images | grep "dev\|none\|test-vp\|peer[0-9]-" | awk '{print $3}')
    if [ -z "$DOCKER_IMAGE_IDS" -o "$DOCKER_IMAGE_IDS" == " " ]; then
        echo "--- no images available for deletion ---"
    else
        docker rmi -f $DOCKER_IMAGE_IDS
    fi
}


function printHelp() {
    echo "Usage: "
    echo "  byfn.sh -m up|down|restart|generate [-c <channel name>] [-t <timeout>] [-d <delay>] [-f <docker-compose-file>] [-s <dbtype>]"
    echo "  byfn.sh -h|--help (print this message)"
    echo "    -m <mode> - one of 'up', 'down', 'restart' or 'generate'"
    echo "      - 'up' - bring up the network with docker-compose up"
    echo "      - 'down' - clear the network with docker-compose down"
    echo "      - 'restart' - restart the network"
    echo "      - 'generate' - generate required certificates and genesis block"
    echo "    -c <channel name> - channel name to use (defaults to \"mychannel\")"
    echo "    -t <timeout> - CLI timeout duration in microseconds (defaults to 10000)"
    echo "    -d <delay> - delay duration in seconds (defaults to 3)"
    echo "    -f <docker-compose-file> - specify which docker-compose file use (defaults to docker-compose-cli.yaml)"
    echo "    -s <dbtype> - the database backend to use: goleveldb (default) or couchdb"
    echo
    echo "Typically, one would first generate the required certificates and "
    echo "genesis block, then bring up the network. e.g.:"
    echo
    echo "    byfn.sh -m generate -c mychannel"
    echo "    byfn.sh -m up -c mychannel -s couchdb"
    echo "    byfn.sh -m down -c mychannel"
    echo
    echo "Taking all defaults:"
    echo "    byfn.sh -m generate"
    echo "    byfn.sh -m up"
    echo "    byfn.sh -m down"
}


function askProceed() {
  read -p "Continue (y/n)? " ans
  case "$ans" in
    y|Y )
      echo "proceeding ..."
    ;;
    n|N )
      echo "exiting..."
      exit 1
    ;;
    * )
      echo "invalid response"
      askProceed
    ;;
  esac
}


function clearArtifacts() {
    rm -rf ./crypto-config
    rm -rf docker-compose-e2e.yaml
}



function generateCerts() {
    which cryptogen
    if [ "$?" -ne 0 ]; then
        echo "cryptogen not found. exiting..."
        exit 1
    fi

    echo 
    echo "###############################################################"
    echo "########### Generating certificates using cryptogen ###########"
    echo "###############################################################"

    cryptogen generate --config=./crypto-config.yaml
    if [ "$?" -ne 0 ]; then
        echo "failed to generate certificates. exiting..."
        exit 1
    fi
}


function replacePrivateKey () {
    ARCH=`uname -s | grep Darwin`
    if [ "$ARCH" == "Darwin" ]; then
        OPTS="-it"
    else
        OPTS="-i"
    fi

    cp docker-compose-e2e-template.yaml docker-compose-e2e.yaml

    CURRENT_DIR=$PWD
    PEER_DIR=$CURRENT_DIR/crypto-config/peerOrganizations
    cd $PEER_DIR
    for i in $(ls); do
        cd ${i%%/}/ca/;
        PRIV_KEY=$(ls *_sk)
        cd $CURRENT_DIR
        sed $OPTS "s/CA1_PRIVATE_KEY/${PRIV_KEY}/g" docker-compose-e2e.yaml
        cd $PEER_DIR
    done
    cd $CURRENT_DIR
    if [ "$ARCH" == "Darwin" ]; then
        rm docker-compose-e2e.yamlt
    fi
}


function generateChannelArtifacts() {
    which configtxgen
    if [ "$?" -ne 0 ]; then
        echo "configtxgen not found. exiting..."
        exit 1
    fi

    echo 
    echo "###############################################################"
    echo "#############  Generating orderer genesis block ###############"
    echo "###############################################################"
    configtxgen -profile TwoOrgsOrdererGenesis -outputBlock ./channel-artifacts/genesis.block
    if [ "$?" -ne 0 ]; then
        echo "failed to generate orderer genesis block. exiting..."
        exit 1
    fi

    echo 
    echo "###############################################################"
    echo "## Generating channel configuration transaction 'channel.tx' ##"
    echo "###############################################################"

    configtxgen -profile TwoOrgsChannel -outputCreateChannelTx ./channel-artifacts/channel.tx -channelID $CHANNEL_NAME
    if [ "$?" -ne 0 ]; then
        echo "failed to generate channel configuration. exiting..."
        exit 1
    fi

    echo 
    echo "###############################################################"
    echo "###############  Generating anchor peer updates ###############"
    echo "###############################################################"
    CURRENT_DIR=$PWD
    PEER_DIR=$CURRENT_DIR/crypto-config/peerOrganizations
    cd $PEER_DIR
    for i in $(ls); do
        ORG=${i%%/};
        cd $CURRENT_DIR
        configtxgen -profile TwoOrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/${ORG}MSPAnchors.tx -channelID $CHANNEL_NAME -asOrg ${ORG}MSP
        if [ "$?" -ne 0 ]; then
            echo "failed to generate anchor peer update. exiting..."
            exit 1
        fi
    done
}



OS_ARCH=$(echo "$(uname -s|tr '[:upper:]' '[:lower:]'|sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')" | awk '{print tolower($0)}')

# Default arg values
CLI_TIMEOUT=10000
CLI_DELAY=3
CHANNEL_NAME="mychannel"
COMPOSE_FILE=docker-compose-cli.yaml
COMPOSE_FILE_COUCH=docker-compose-couch.yaml

# Parse commandline args
while getopts "h?m:c:t:d:f:s:" opt; do
  case "$opt" in
    h|\?)
      exit 0
    ;;
    m)  MODE=$OPTARG
    ;;
    c)  CHANNEL_NAME=$OPTARG
    ;;
    t)  CLI_TIMEOUT=$OPTARG
    ;;
    d)  CLI_DELAY=$OPTARG
    ;;
    f)  COMPOSE_FILE=$OPTARG
    ;;
    s)  IF_COUCHDB=$OPTARG
    ;;
  esac
done


# Determine whether starting, stopping, restarting or generating
if [ "$MODE" == "up" ]; then
  EXPMODE="Starting"
  elif [ "$MODE" == "down" ]; then
  EXPMODE="Stopping"
  elif [ "$MODE" == "restart" ]; then
  EXPMODE="Restarting"
  elif [ "$MODE" == "generate" ]; then
  EXPMODE="Generating cert files and genesis block for"
else
  printHelp
  exit 1
fi


# Announce what was requested
if [ "${IF_COUCHDB}" == "couchdb" ]; then
    echo
    echo "${EXPMODE} channel '${CHANNEL_NAME}' with CLI timeout of '${CLI_TIMEOUT}' using database '${IF_COUCHDB}'"
else
    echo "${EXPMODE} channel '${CHANNEL_NAME}' with CLI timeout of '${CLI_TIMEOUT}'"
fi

# Ask for confirmation to proceed
askProceed


# Create the network using docker compose
if [ "${MODE}" == "generate" ]; then
    # clearArtifacts
    generateCerts
    replacePrivateKey
    generateChannelArtifacts
elif [ "${MODE}" == "up" ]; then
    networkUp
elif [ "${MODE}" == "down" ]; then
    networkDown
elif [ "${MODE}" == "restart" ]; then
    networkDown
    networkUp
else
    printHelp
    exit 1
fi
