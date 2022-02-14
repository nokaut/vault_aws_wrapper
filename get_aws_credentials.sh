#!/bin/bash

# Add to .aws/config config:
#
# [profile mainprofile]
# region=eu-west-1
# credential_process=/usr/local/bin/get_aws_credentials.sh --vault_aws_profile mainprofile --vault_aws_role terraform

LOCK_FILE=/tmp/vault_file_session.lock
CREDENTIALS=/tmp/vault_file_session.session
TOKEN_ACTIVE=0
VAULT_AWS_PROFILE=''
VAULT_AWS_ROLE=''
VAULT_SESSION_DIR=/tmp

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

LOCK_FILE=${VAULT_SESSION_DIR}/vault_${VAULT_AWS_PROFILE}_${VAULT_AWS_ROLE}_session.lock
SESSION_RELEASE_FILE=${VAULT_SESSION_DIR}/vault_${VAULT_AWS_PROFILE}_${VAULT_AWS_ROLE}_session.release
CREDENTIALS=${VAULT_SESSION_DIR}/vault_${VAULT_AWS_PROFILE}_${VAULT_AWS_ROLE}_session.session

if [ -f "$LOCK_FILE" ]; then
  starttime=$(tail -n 1 $LOCK_FILE)
  lease_duration=$(head -n 1 $LOCK_FILE)
  timediff=$(($(date +"%s")-$starttime))
  if (( $timediff < $lease_duration )); then
      echo " $timediff > $lease_duration " > $SESSION_RELEASE_FILE
      TOKEN_ACTIVE=1
  else
      rm $LOCK_FILE $SESSION_RELEASE_FILE $CREDENTIALS
  fi
fi

if [ $TOKEN_ACTIVE -eq 0 ]; then
  json_result=$(vault read ${VAULT_AWS_PROFILE}/creds/${VAULT_AWS_ROLE} -format=json)
  echo $(echo $json_result | jq -r ".lease_duration") > $LOCK_FILE
  echo $(date +"%s") >> ${LOCK_FILE}
  AWS_ACCESS_KEY_ID=$( echo $json_result | jq -r ".data.access_key")
  AWS_SECRET_ACCESS_KEY=$( echo $json_result | jq -r ".data.secret_key")
  echo '{ "Version": 1, "AccessKeyId": "'"${AWS_ACCESS_KEY_ID}"'", "SecretAccessKey": "'"${AWS_SECRET_ACCESS_KEY}"'" }' > $CREDENTIALS
  chmod 600 $CREDENTIALS
  sleep 15
fi

cat $CREDENTIALS

