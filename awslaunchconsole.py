#!/usr/bin/env python3
import boto3
import boto3.session
import botocore
import json
import requests
import sys
import webbrowser

from botocore.exceptions import ClientError
from urllib.parse import urlencode

# You should change this
issuer_url = 'https://nokaut.pl'

console_url = 'https://console.aws.amazon.com/'
sign_in_url = 'https://signin.aws.amazon.com/federation'


session = boto3.session.Session()
try:
    creds = session.get_credentials()
except botocore.exceptions.CredentialRetrievalError as e:
    print("\n  You have to get valid AWS Session token. ")
    print("  You can get it from: `get_aws_credentials.sh`, `Vault`, `aws-vault`, or via `awscli` \n")
    sys.exit(1)

creds = creds.get_frozen_credentials()

awsdata = {'sessionId': creds.access_key,
           'sessionKey': creds.secret_key,
           'sessionToken': creds.token}

params = {'Action': 'getSigninToken','Session': json.dumps(awsdata)}

response = requests.get(url=sign_in_url, params=params)

ds = json.loads(response.text)
ds['Action'] = 'login'
ds['Issuer'] = issuer_url
ds['Destination'] = console_url
uri = sign_in_url + '?' + urlencode(ds)

webbrowser.open(uri)
