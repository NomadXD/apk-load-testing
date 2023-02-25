set -e
script_dir=$(dirname "$0")
root_dir="${script_dir}/.."
# Change directory to make sure logs directory is created inside $script_dir
cd $script_dir

user_count=10
heap_size="1g"
duration=1200
payload_size=50B
host=3.141.180.55
server_ips="192.168.11.64"

function usage() {
    echo ""
    echo "Usage: "
    echo "$0 [-u <user_count>] [-s <payload_size>]"
    echo ""
    echo "-u: User Count."
    echo "-s: The Payload Size."
    echo "-h: Display this help and exit."
    echo ""
}

while getopts "u:s:h" opts; do
    case $opts in
    u)
        user_count=${OPTARG}
        ;;
    s)
        payload_size=${OPTARG}
        ;;
    h)
        usage
        exit 0
        ;;
    \?)
        usage
        exit 1
        ;;
    esac
done

if [[ -z $user_count ]]; then
    echo "Please specify user count."
    exit 1
fi

if [[ -z $payload_size ]]; then
    echo "Please specify payload size."
    exit 1
fi

# Local Machine
## Create deployment
cd "${root_dir}/k8s-artifacts"
kubectl delete -f choreo-connect/ # -f netty-backend/
kubectl apply -f choreo-connect/ # -f netty-backend/
sleep 120
kubectl get po

results_dir="${root_dir}/results/passthrough/${heap_size}_heap/${user_count}_users/${payload_size}/0ms_sleep"
echo "Results Dir: ${results_dir}"
mkdir -p ${results_dir}
kubectl top po --containers > "${results_dir}/start-resources.txt"
nohup sh -c "sleep 30 && kubectl top po --containers > ${results_dir}/10min-resources.txt" > /dev/null &

# Client
ssh cc-perf-test-client-1 \
    heap_size=$heap_size user_count=$user_count payload_size=$payload_size duration=$duration host=$host server_ips=$server_ips \
    'bash -s' <<'ENDSSH'
echo ""
echo ""
echo "Start Test"
echo "HOME: ${HOME}"
echo "Heap: ${heap_size}"
echo "Users: ${user_count}"
echo "Paylod: ${payload_size}"

export HEAP="-Xms${heap_size} -Xmx${heap_size}"

results_dir="${HOME}/results/passthrough/${heap_size}_heap/${user_count}_users/${payload_size}/0ms_sleep"
echo "Results Dir: ${results_dir}"

user_count_per_server=$(($user_count / 2))
echo "Users per server: ${user_count_per_server}"

cd ./apache-jmeter-5.5/bin
./jmeter -n -t ${HOME}/apim-test.jmx \
    -j "${results_dir}/jmeter.log" \
    -Gusers=$user_count_per_server \
    -Gduration=$duration \
    -Ghost=$host \
    -GhostHeader=gw.wso2.com \
    -Gport=443 \
    -Gpath=/echo/1.0.0 \
    -Gpayload="${HOME}/${payload_size}.json" \
    -Gresponse_size=$payload_size \
    -Gprotocol=https \
    -Gtokens=${HOME}/jwt-tokens.csv \
    -l "${results_dir}/results.jtl" \
    -R "${server_ips}"
ENDSSH

kubectl top po --containers > "${results_dir}/end-resources.txt"