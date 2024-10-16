#!/bin/bash

# Function to generate accounts
create_accounts() {
    echo "Generating accounts..."
    miners=$1
    clients=$2
    data_dir=$3  # Default data directory
    password_length=$4  # Default password length
    local bc_script="../../setup/networks/middlewares/create_accounts.py"
    echo $miners
    # Remove existing data directory
    rm -rf "$data_dir"

    # Call geth to generate accounts
    python3 $bc_script --miners $miners --clients $clients --data-dir $data_dir --password-length $password_length
    echo $data_dir
}
# create @ for a new task publisher
create_account_task_publisher(){
    echo "Creating account for a new task publisher..."
    data_dir=$1
    password_length=$2
    local file_path="../../setup/networks/middlewares/create_account_task_publisher.py"
    python3 $file_path --data-dir $data_dir --password-length $password_length
}


# Function to update accounts balance in the genesis files
update_accounts_balance() {
    echo "Updating genesis files..."
    # genesis is the path to the directory containing the genesis file
    genesis=$1 # Default genesis path
    balance=$2  # Default balance
    data_dir=$3  # Default data directory for geth clients
    consensus="poa"
    local update_accounts_balance_script="../../setup/networks/middlewares/update_accounts_balance.py"

    # Ensure datadir is defined if not provided as an argument
    if [[ -z "$data_dir" ]]; then
        echo "Error: a datadir for geth client should be provided"
        exit 1
    fi
    src="${genesis}/genesis_poa.json"
    dst="${data_dir}/genesis_poa.json"
    # Call the update_genesis function from bc python script
    python3 $update_accounts_balance_script --src $src --dst $dst --consensus $consensus --balance $balance --data-dir $data_dir
    if [[ $? -ne 0 ]]; then  # Check for errors
    echo "Error updating genesis file for consensus: $consensus"
    exit 1
    fi

}

 #Function to build Docker image for the BC Node
build_bc_node_image() {
    local bcNode_dockerfile="../../setup/networks/docker/Dockerfile.bcNode"
    echo "Building Docker image for BC Node..."
    echo "Dockerfile Path: $bcNode_dockerfile"
    # Build Docker image for geth node
    docker build -f "$bcNode_dockerfile" -t "bc-node" "../.."
}

# Function to build Docker image for the FL Node
build_fl_node_image() {
    local bfl_dockerfile="../../setup/networks/docker/Dockerfile.flNode"
    echo "Building Docker image for FL Node..."
    echo "Dockerfile Path: $bfl_dockerfile"
    # Build Docker image for FL node
    docker build -f "$bfl_dockerfile" -t "fl-node" "../.."
}


# create a docker network
create_docker_network() {
    network_name=$1
    driver=$2
    subnet=$3
    docker network create \
        --driver=$driver \
        --subnet=$subnet \
        $network_name
}

## launch docker container , the ones establishing the BC network
start_bc_containers(){
    local miners=$1  # Accept MINERS as an argument
    local networkid=$2  # Accept NETWORK_ID as an argument
    local blockchain_yml="../../setup/networks/docker-compose/bc.yml"  # full path to bc.yml
    NETWORK_ID=$networkid MINERS=$miners docker compose -f $blockchain_yml -p one up  --remove-orphans 
    ##--build
}

# Function to connect peers
connect_peers() {
    echo "Connecting peers..."
    local network=$1
    local connect_peers_script="../../setup/networks/middlewares/connect_peers.py"
    python3 $connect_peers_script --network $network

}
 

# Function to split data between clients simulating the FL 
split_data() {
    echo "Splitting data ..."
    local dataset=$1
    local n_parties=$2
    local partition=$3
    local beta=$4
    local datadir=$5
    echo $n_parties
    local split_data_script="../../federated_learning/regular_user/data_manipulation//splitData.py"
    python3 $split_data_script --dataset $dataset --n_parties $n_parties --partition $partition --beta $beta --datadir $datadir 

}


#Funtion to launch federated learning containers
start_trainers_containers(){
    echo "Launching Federated learning containers..."
    local contract_address=$1
    local abi=$2
    local abi_file=$3
    local contract_address_reputation=$4
    local abi_reputation=$5
    local abi_file_reputation=$6
    local contract_address_oracle=$7
    local abi_oracle=$8
    local abi_file_oracle=$9
    local trainers=${10}
    local admins_number=${11}
    local evaluation_name=${12}
    local task=${13}
    echo $task
    local fl_yml="../../setup/networks/docker-compose/fl.yml"  # full path to fl.yml
    CONTRACT=$contract_address ABI=$abi ABI_FILE=$abi_file CONTRACT_REPUTATION=$contract_address_reputation ABI_REP=$abi_reputation ABI_FILE_REP=$abi_file_reputation CONTRACT_ORACLE=$contract_address_oracle ABI_ORACLE=$abi_oracle ABI_FILE_ORACLE=$abi_file_oracle ADMINS=$admins_number CLIENTS=$trainers EVALUATION_NAME=$evaluation_name TASK=$task docker compose -f $fl_yml -p federated_learning up --remove-orphans 
}

#function to register federated learning trainers into a the BFL system
register_trainers(){
    echo "Launching Federated learning containers..."
    local contract_address=$1
    local abi=$2
    local abi_file=$3
    local trainers=${4}
    local admins_number=${5}
    local fl_yml="../../setup/networks/docker-compose/fl_register.yml"  # full path to fl.yml
    CONTRACT=$contract_address ABI=$abi ABI_FILE=$abi_file ADMINS=$admins_number CLIENTS=$trainers docker compose -f $fl_yml -p federated_learning up --remove-orphans 
}


#Function to launch task publisher container 
start_task_publisher_containers(){
    echo "Launching task publisher container..."
    local contract_address=$1
    local task_publisher_numbers=$2
    local abi=$3
    local abi_file=$4
    local rounds=$5
    local requiredTrainers=$6
    local task_yml="../../setup/networks/docker-compose/taskp.yml"  # full path to taskp.yml
    CONTRACT=$contract_address TASKPUBLISHERS=$task_publisher_numbers ABI=$abi ROUNDS=$rounds ABI_FILE=$abi_file TRAINERS=$requiredTrainers docker compose -f $task_yml -p task up --remove-orphans 
}


# Funtion that allows the operator contract to authorize the oracle node as a sender 
authorize_operator(){
    echo "Launching admin container..."
    local contract_address=$1
    local admins_number=$2
    local abi=$3
    local abi_file=$4
    local oracle_node_address=$5
    echo $contract_address
    local admin_yml="../../setup/networks/docker-compose/admin.yml"  # full path to admin.yml
    CONTRACT_ORACLE=$contract_address ADMINS=$admins_number ABI_ORACLE=$abi ABI_FILE_ORACLE=$abi_file ORACLE_NODE_ADDRESS=$oracle_node_address docker compose -f $admin_yml -p admin up --remove-orphans 
}




declare -A function_params

# Predefined parameters for functions necessary to set up a blockchain network with a single layer , in case of L2 skip all these commands
function_params[create_accounts]="4 4 ../../setup/L1/blockchain/datadir 15"
function_params[create_account_task_publisher]="../../setup/L1/blockchain/datadir 15" 
function_params[update_accounts_balance]="../../setup/L1/blockchain 1000000000000000000000 ../../setup/L1/blockchain/datadir"
function_params[create_docker_network]="BCFL bridge 172.16.240.0/20"
function_params[build_bc_node_image]=""
function_params[start_bc_containers]="4 4444" 
function_params[connect_peers]="8fdf1946a39b"

# Predefined parameters for function necessary to authorize the oracle operator node
function_params[authorize_operator]="0xD4DC4279550c46aC7C77B3F85d63641C1F48E9d7 1 Operator Operator 0x014F38e6C4767D792D62A19786596324B03becFF"

# docker rm $(docker ps -a -q)
# Predefined parameters for functions necessary to set up the FL business logic
function_params[build_fl_node_image]="" ## run it only once
function_params[split_data]="mnist 1000 noniid-labeldir 0.5 ../../federated_learning/regular_user/data_manipulation/data/ " ## run it only once to simulate the trainers having their own datasets and that's it 
function_params[register_trainers]="0xa2B79890008670e8C82B98726A0e8F9AC3E2CbF0 BusinessLogic businessLogic 5 1"
function_params[start_task_publisher_containers]="0xa2B79890008670e8C82B98726A0e8F9AC3E2CbF0 1 BusinessLogic businessLogic 20 5"
function_params[start_trainers_containers]="0xa2B79890008670e8C82B98726A0e8F9AC3E2CbF0 BusinessLogic businessLogic 0xBE6Fc9B483329b65e7be1747a7B12193820e8654 ManageReputation manageRep  0xC4241F50A0d91c57C75C39df4f0fBA90483256Af APIConsumer APIconsumer 5 1 accuracy 333"


# Main logic to dispatch functions based on command-line arguments
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <function_name>"
    exit 1
fi

# Get the function name from the first argument
function_name=$1

# Call the corresponding function with its parameters
case "$function_name" in
    create_accounts)
        create_accounts ${function_params[$function_name]}
        ;;
    create_account_task_publisher)
        create_account_task_publisher ${function_params[$function_name]}
        ;;
    update_accounts_balance)
        update_accounts_balance ${function_params[$function_name]}
        ;;
    create_docker_network)
        create_docker_network ${function_params[$function_name]}
        ;;
    build_bc_node_image)
        build_bc_node_image ${function_params[$function_name]}
        ;;
    start_bc_containers)
        start_bc_containers ${function_params[$function_name]}
        ;;
    connect_peers)
        connect_peers ${function_params[$function_name]}
        ;;

    authorize_operator)
        authorize_operator ${function_params[$function_name]}
        ;;

    build_fl_node_image)
        build_fl_node_image ${function_params[$function_name]}
        ;;
    split_data)
        split_data ${function_params[$function_name]}
        ;;
    start_task_publisher_containers)
        start_task_publisher_containers ${function_params[$function_name]}
        ;;
    start_trainers_containers)
        start_trainers_containers ${function_params[$function_name]} "$2"
        ;;
    register_trainers)
        register_trainers ${function_params[$function_name]} "$2"
        ;;
    *)
        echo "Function '$function_name' not found."
        ;;
esac

