#!/usr/bin/bash

programname=$0
function usage {
    echo ""
    echo "Perfoms API calls to login to Harmony Endpoint in the Infinity Portal and list computers that has a name that contains 'c'"
    echo ""
    echo "usage: $programname --clientid string --secretkey string --url string"
    echo ""
    echo "  --clientid string       Client ID"
    echo "                         "
    echo "  --secretkey string      Secret Key, sometimes called Access Key"
    echo "                         "
    echo "  --url string            Authentication URL for Infinity Portal"
    echo "                          (example: https://cloudinfra-gw.portal.checkpoint.com/auth/external)"
    echo ""
}

function die {
    printf "Script failed: %s\n\n" "$1"
    exit 1
}

while [ $# -gt 0 ]; do
    if [[ $1 == "--"* ]]; then
        v="${1/--/}"
        declare "$v"="$2"
        shift
    fi
    shift
done


if [[ -z $clientid ]]; then
    usage
    die "Missing parameter --clientid"
elif [[ -z $secretkey ]]; then
    usage
    die "Missing parameter --secretkey"
elif [[ -z $url ]]; then
    usage
    die "Missing parameter --url"
fi

base_url=$(awk -F/ '{print $3}' <<<"$url")

# Create JSON for login API call
ip_login_data=$(jq -n --arg clientId "$clientid" --arg accessKey "$secretkey" '{clientId: $clientId, accessKey: $accessKey}')
header_accept_json="accept: application/json"
header_content_json="Content-Type: application/json"

# perform login to infinity portal (ip) with relevant headers and payload
ip_login_response=$(curl -s -X POST "$url" -H "$header_accept_json" -H "$header_content_json" -d "$ip_login_data")

# using jq to get the token and assign it to the variable token. the -r flag is needed to remove the "" that would otherwise enclose the data from ip_login_response
ip_token=$(jq -r '.data.token' <<< $ip_login_response)
header_auth_bearer="Authorization: Bearer $ip_token"
ep_api_login_url="https://cloudinfra-gw.portal.checkpoint.com/app/endpoint-web-mgmt/harmony/endpoint/api/v1/session/login/cloud"

# Send API request to login to Endpoint API
ep_api_response=$(curl -s -X POST "$ep_api_login_url" -H "$header_accept_json" -H "$header_auth_bearer")

#Format data for API request to filter computers with a name that contains "C" 
ep_token=$(jq -r '.apiToken' <<< $ep_api_response)
computers_endpoint="/app/endpoint-web-mgmt/harmony/endpoint/api/v1/asset-management/computers/filtered"
computers_url="https://$base_url$computers_endpoint"
header_mgmt_job="x-mgmt-run-as-job: on"
header_ep_token="x-mgmt-api-token: $ep_token"
payload_computers_filtered='{
		  "filters": [
        			{
		                    "columnName": "computerName",
				    "filterValues": [
				                      "C"
	  					      ],
		                    "filterType": "Contains"
														                                                        }
														                                                    ],
		   "paging": {
		               "pageSize": 10,
		               "offset": 0
		             }
		   }'

# Send API request to get data
computers_response=$(curl -s -X 'POST' "$computers_url" -H "$h1" -H "$header_mgmt_job" -H "$header_auth_bearer" -H "$header_ep_token" -H "$header_content_json" -d "$payload_computers_filtered")

# API request resonse contains jobId that we need to view the actuall data.

# Get jobId
computers_jobid=$(jq -r '.jobId' <<< $computers_response)
# URI for jobs
jobs_endpoint="/app/endpoint-web-mgmt/harmony/endpoint/api/v1/jobs/"
# URL for jobs with out jobId
jobs_base_url="https://$base_url$jobs_endpoint"
# URL for jobs with jobId
jobs_url="$jobs_base_url$computers_jobid"
# Send API request to check status of job
jobs_response=$(curl -s "$jobs_url" -H "$headers_accept_json" -H "$header_auth_bearer" -H "$header_ep_token" )
jobs_status=$(jq -r '.status' <<< $jobs_response)

# Check if API call to job is still executing, in that case wait 2 seconds.
while [[ $jobs_status == 'IN_PROGRESS' ]]
do
	sleep 2
	jobs_response=$(curl -s "$jobs_url" -H "$headers_accept_json" -H "$header_auth_bearer" -H "$header_ep_token" )
	jobs_status=$(jq -r '.status' <<< $jobs_response)
done	

# Print result and format uring jq
echo $jobs_response | jq '.' 


