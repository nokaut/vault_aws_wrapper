#!/usr/bin/env python3
import boto3
import boto3.session
import json
import requests
import webbrowser

from urllib.parse import urlencode

# You should change this
issuer_url = 'https://nokaut.pl'

console_url = 'https://console.aws.amazon.com/'
sign_in_url = 'https://signin.aws.amazon.com/federation'

session = boto3.session.Session()
creds = session.get_credentials()
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
