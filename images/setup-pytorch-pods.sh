#!/bin/bash
# Copyright 2020 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

NUM_CORES=$(echo "${ACCELERATOR_TYPE}" | egrep -o "[0-9]*" | tail -1)
NUM_CORES_PER_HOST=8
INSTANCE_GROUP_SIZE=$(expr "${NUM_CORES}" / "${NUM_CORES_PER_HOST}")

export INSTANCE_TEMPLATE_NAME="instance-template-${RESOURCE_SUFFIX}"
echo "Creating GCE Instance Template: ${INSTANCE_TEMPLATE_NAME}"
# Make sure it has PD with the dataset
gcloud compute --project="${PROJECT}" \
  instance-templates \
  create \
  "${INSTANCE_TEMPLATE_NAME}" \
  --machine-type="${MACHINE_TYPE}" \
  --maintenance-policy=MIGRATE \
  --scopes=https://www.googleapis.com/auth/cloud-platform \
  --image-family=torch-xla \
  --image-project=ml-images \
  --boot-disk-size=200GB \
  --boot-disk-type=pd-standard \
  --boot-disk-device-name="${INSTANCE_TEMPLATE_NAME}" \
  --reservation-affinity=any

export TPU_POD_NAME="tpu-pod-${RESOURCE_SUFFIX}"
echo "Creating TPU Pod: ${TPU_POD_NAME}"
gcloud compute --project="${PROJECT}" \
  tpus \
  create \
  "${TPU_POD_NAME}" \
  --network=default \
  --accelerator-type="${ACCELERATOR_TYPE}" \
  --version="${RUNTIME_VERSION}" \
  --zone="${ZONE}" \
  --async

export INSTANCE_GROUP_NAME="instance-group-${RESOURCE_SUFFIX}"
echo "Creating GCE Instance Group: ${INSTANCE_GROUP_NAME}"

gcloud compute --project="${PROJECT}" \
  instance-groups \
  managed \
  create \
  "${INSTANCE_GROUP_NAME}" \
  --base-instance-name="${INSTANCE_GROUP_NAME}" \
  --template="${INSTANCE_TEMPLATE_NAME}" \
  --size="${INSTANCE_GROUP_SIZE}" \
  --zone="${ZONE}"

echo "Waiting for TPU Pod ${TPU_POD_NAME} to become healthy"
WFH_TIMEOUT=600
PROJECT=${PROJECT} TPU_POD_NAME=${TPU_POD_NAME} ZONE=${ZONE} \
  timeout "${WFH_TIMEOUT}" \
  bash -c 'while [[ ${health:-NONE} != "HEALTHY" ]]; \
    do sleep 10 && \
    health=$(gcloud \
      --project=${PROJECT} \
      compute \
      tpus \
      describe \
      ${TPU_POD_NAME} \
      --zone=${ZONE} \
      --format="value(health)") && \
    echo "Waiting for healthy TPU (current health ${health:-NONE})..."; done'


if [[ $? -ne 0 ]]; then
  echo "TPU failed to become healthy."
fi
