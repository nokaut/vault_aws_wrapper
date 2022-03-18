#!/usr/bin/env bash

# Add to .aws/config config:
#
# [profile mainprofile]
# region=eu-west-1
# credential_process=/usr/local/bin/get_aws_credentials.sh --vault_aws_profile mainprofile --vault_aws_role terraform
#
# [profile roleprofile]
# region=eu-west-1
# credential_process=/usr/local/bin/get_aws_credentials.sh --vault_aws_profile roleprofile --vault_aws_role administrator --arn_role arn:aws:iam::111111111111:role/admin

# We have to use different date binary for MacOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    DATE=$(which gdate)
    STATUS=$?
    if [ $STATUS -gt 0 ]; then
        printf "Probably missing gdate binary.\nPlease install it with brew.\n"
        exit 1
    fi
else
    DATE=$(which date)
fi

# Check valid vault token
vault token lookup &>/dev/null
EXITCODE=$?
if [ $EXITCODE -eq 2 ]; then
    echo -e "\n You need to auth in vault. Try to run command:\n vault login -method=ldap username=**** \n"
    exit $EXITCODE
fi

VAULT_SESSION_DIR="${HOME}/.vault_sessions"
LOCK_FILE="${VAULT_SESSION_DIR}/vault_file_session.lock"
CREDENTIALS="${VAULT_SESSION_DIR}/vault_file_session.session"
TOKEN_ACTIVE=0
VAULT_AWS_PROFILE=''
VAULT_AWS_ROLE=''
DURATION_SECONDS=900

parse_args() {
    case "$1" in
        --vault_aws_profile)
            VAULT_AWS_PROFILE="$2"
            ;;
        --vault_aws_role)
            VAULT_AWS_ROLE="$2"
            ;;
        --vault_session_dir)
            VAULT_SESSION_DIR="$2"
            ;;
        --arn_role)
            AWS_ARN_ROLE="$2"
            ;;
        --duration_seconds)
            DURATION_SECONDS="$2"
            ;;
        *)
            echo "Unknown or badly placed parameter '$1'." 1>&2
            exit 1
            ;;
    esac
}

while [[ "$#" -ge 2 ]]; do
    parse_args "$1" "$2"
    shift; shift
done

# Prepare directory for vault sessions
mkdir -p ${VAULT_SESSION_DIR} && chmod 700 ${VAULT_SESSION_DIR}

LOCK_FILE=${VAULT_SESSION_DIR}/vault_${VAULT_AWS_PROFILE}_${VAULT_AWS_ROLE}_session.lock
SESSION_RELEASE_FILE=${VAULT_SESSION_DIR}/vault_${VAULT_AWS_PROFILE}_${VAULT_AWS_ROLE}_session.release
CREDENTIALS=${VAULT_SESSION_DIR}/vault_${VAULT_AWS_PROFILE}_${VAULT_AWS_ROLE}_session.session

if [ -f "$LOCK_FILE" ]; then
  starttime=$(tail -n 1 $LOCK_FILE)
  lease_duration=$(head -n 1 $LOCK_FILE)
  timediff=$(($(${DATE} +"%s")-$starttime))
  if (( $timediff < $lease_duration )); then
      echo " $timediff > $lease_duration " > $SESSION_RELEASE_FILE
      TOKEN_ACTIVE=1
  else
      rm -f $LOCK_FILE $SESSION_RELEASE_FILE $CREDENTIALS
  fi
fi

if [ $TOKEN_ACTIVE -eq 0 ]; then
  json_result=$(vault read ${VAULT_AWS_PROFILE}/creds/${VAULT_AWS_ROLE} -format=json)
  echo $(echo $json_result | jq -r ".lease_duration") > $LOCK_FILE
  echo $(${DATE} +"%s") >> ${LOCK_FILE}
  export AWS_ACCESS_KEY_ID=$( echo $json_result | jq -r ".data.access_key")
  export AWS_SECRET_ACCESS_KEY=$( echo $json_result | jq -r ".data.secret_key")
  sleep 10

  if [ -z $AWS_ARN_ROLE ];
  then
    echo '{ "Version": 1, "AccessKeyId": "'"${AWS_ACCESS_KEY_ID}"'", "SecretAccessKey": "'"${AWS_SECRET_ACCESS_KEY}"'" }' > $CREDENTIALS
  else
    export AWS_SECURITY_TOKEN=$( echo $json_result | jq -r ".data.security_token")
    STS_RESULT=$(aws sts assume-role --role-arn ${AWS_ARN_ROLE} --role-session-name ${VAULT_AWS_PROFILE}_${VAULT_AWS_ROLE}_${AWS_ACCESS_KEY_ID} --duration-seconds ${DURATION_SECONDS})
    AWS_ACCESS_KEY_ID=$( echo ${STS_RESULT} | jq -r ".Credentials.AccessKeyId")
    AWS_SECRET_ACCESS_KEY=$( echo ${STS_RESULT} | jq -r ".Credentials.SecretAccessKey")
    AWS_SESSION_TOKEN=$(echo ${STS_RESULT} | jq -r ".Credentials.SessionToken")
    AWS_EXPIRATION_TOKEN=$(echo ${STS_RESULT} | jq -r ".Credentials.Expiration")

    AWS_EXPIRATION_TOKEN_SEC=$(${DATE} --utc -d"${AWS_EXPIRATION_TOKEN}" +%s)
    AWS_EXPIRATION_TOKEN_SEC_DIFF=$(($AWS_EXPIRATION_TOKEN_SEC-$(${DATE} --utc +"%s")))
    echo ${AWS_EXPIRATION_TOKEN_SEC_DIFF} > $LOCK_FILE
    echo $(${DATE} +"%s") >> ${LOCK_FILE}
    echo '{ "Version": 1, "AccessKeyId": "'"${AWS_ACCESS_KEY_ID}"'", "SecretAccessKey": "'"${AWS_SECRET_ACCESS_KEY}"'", "SessionToken": "'"${AWS_SESSION_TOKEN}"'", "Expiration": "'"${AWS_EXPIRATION_TOKEN}"'" }' > $CREDENTIALS
  fi
  chmod 600 $CREDENTIALS
  sleep 5
fi

cat $CREDENTIALS
