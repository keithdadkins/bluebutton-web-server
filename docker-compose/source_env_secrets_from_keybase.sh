#!/bin/bash

# Source ENV secrets for BFD & SLSx, and copy certfiles to local development
#
# NOTE:
#
#   1. You must be logged in to Keybase and have the BB2 team file system mounted.
#
#   2. You must also be connected to the VPN.
#
# SETTINGS:  You may need to customize these for your local setup.

KEYBASE_ENV_FILE="team/bb20/infrastructure/creds/source_ENV_secrets_for_local_development.env"
KEYBASE_CERTFILES_SUBPATH="team/bb20/infrastructure/certs/local_development/fhir_client/"

export CERTSTORE_TEMPORARY_MOUNT_PATH="./docker-compose/certstore"
export DJANGO_FHIR_CERTSTORE="/code/docker-compose/certstore"

CERT_FILENAME="client_data_server_bluebutton_local_certificate.pem"
KEY_FILENAME="client_data_server_bluebutton_local_private_key.pem"

# Echo function that includes script name on each line for console log readability
echo_msg () {
    echo "$(basename $0): $*"
}

# main

# Set bash builtins for safety
set -e -u -o pipefail

# Set KeyBase ENV path based on your type of system
SYSTEM=$(uname -s)

echo_msg " - Setting Keybase location based on SYSTEM type: ${SYSTEM}"
echo_msg

if [[ ${SYSTEM} == "Linux" ]]
then
  keybase_env_path="/keybase"
elif [[ ${SYSTEM} == "Darwin" ]]
then
  keybase_env_path="/Volumes/keybase"
else
    # support cygwin
    keybase_env_path="/cygdrive/k"
fi

# Keybase ENV file
keybase_env="${keybase_env_path}/${KEYBASE_ENV_FILE}"

echo_msg " - Sourcing ENV secrets from: ${keybase_env}"
echo_msg

# Check that ENV file exists in correct location
if [ ! -f "${keybase_env}" ]
then
    echo_msg
    echo_msg "ERROR: The ENV secrets could NOT be found at: ${keybase_env}"
    echo_msg
    exit 1
fi

# Source ENVs
source "${keybase_env}"

# Check ENV vars have been sourced
if [ -z "${DJANGO_USER_ID_SALT}" ]
then
    echo_msg "ERROR: The DJANGO_USER_ID_SALT variable was not sourced!"
    exit 1
fi
if [ -z "${DJANGO_USER_ID_ITERATIONS}" ]
then
    echo_msg "ERROR: The DJANGO_USER_ID_ITERATIONS variable was not sourced!"
    exit 1
fi

# Check temp certstore dir and create if not existing
if [ -d "${CERTSTORE_TEMPORARY_MOUNT_PATH}" ]
then
    echo_msg
    echo_msg "  - OK: The temporary certstore mount path is found at: ${CERTSTORE_TEMPORARY_MOUNT_PATH}"
else
    mkdir ${CERTSTORE_TEMPORARY_MOUNT_PATH}
    echo_msg
    echo_msg "  - OK: Created the temporary certstore mount path at: ${CERTSTORE_TEMPORARY_MOUNT_PATH}"
fi


# Keybase cert files
keybase_certfiles="${keybase_env_path}/${KEYBASE_CERTFILES_SUBPATH}"
keybase_cert_file="${keybase_certfiles}/${CERT_FILENAME}"
keybase_key_file="${keybase_certfiles}/${KEY_FILENAME}"

# Check that certfiles in keybase dir exist
if [ -f "${keybase_cert_file}" ]
then
    echo_msg
    echo_msg "  - OK: The cert file was found at: ${keybase_cert_file}"
else
    echo_msg
    echo_msg "ERROR: The cert file could NOT be found at: ${keybase_cert_file}"
    exit 1
fi

if [ -f ${keybase_key_file} ]
then
    echo_msg
    echo_msg "  - OK: The key file was found at: ${keybase_key_file}"
else
    echo_msg
    echo_msg "ERROR: The key file could NOT be found at: ${keybase_key_file}"
    exit 1
fi

# Copy certfiles from KeyBase to local for container mount
echo_msg "  - COPY certfiles from KeyBase to local temp for container mount..."
echo_msg
cp ${keybase_cert_file} "${CERTSTORE_TEMPORARY_MOUNT_PATH}/ca.cert.pem"
cp ${keybase_key_file} "${CERTSTORE_TEMPORARY_MOUNT_PATH}/ca.key.nocrypt.pem"