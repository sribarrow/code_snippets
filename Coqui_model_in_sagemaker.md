# Coqui XTTS-v2 Large Model Copy and SageMaker `model.tar.gz` Procedure

This runbook documents how to copy/download the Coqui XTTS-v2 large model, package it as a SageMaker `model.tar.gz`, and upload it to S3 for use with a SageMaker GPU real-time endpoint.

## Public references vs private placeholders

Public/common references are intentionally left as-is, for example:

```text
coqui/XTTS-v2
tts_models--multilingual--multi-dataset--xtts_v2
/opt/ml/model
ml.g5.xlarge
COQUI_TOS_AGREED
USE_CUDA
```

Anything specific to an AWS account, project, local Docker Compose setup, S3 bucket, ECR repository, or endpoint should be replaced with a placeholder.

## Placeholders

Replace the placeholders below with values from your environment:

```text
<YOUR_MODEL_BUCKET>        S3 bucket for SageMaker model artifacts
<COQUI_MODELS_VOLUME>      Docker volume that contains the local Coqui model cache
<COMPOSE_PROJECT>          Docker Compose project prefix, if Compose created the volume
<GPU_INSTANCE_TYPE>        SageMaker GPU instance type, for example ml.g5.xlarge
```


## Target outcome

At the end of this procedure, you should have:

```text
model.tar.gz
```

uploaded to:

```text
s3://<YOUR_MODEL_BUCKET>/coqui/xtts-v2/model.tar.gz
```

When SageMaker loads this model artifact, it should extract to:

```text
/opt/ml/model/tts_models--multilingual--multi-dataset--xtts_v2/
```

Your container should then use:

```text
MODEL_PATH=/opt/ml/model/tts_models--multilingual--multi-dataset--xtts_v2
CONFIG_PATH=/opt/ml/model/tts_models--multilingual--multi-dataset--xtts_v2/config.json
USE_CUDA=true
COQUI_TOS_AGREED=1
```

---

## Option A: Copy the model from an existing Docker volume

Use this option if you have already run Coqui locally and the model exists in a Docker volume.

Example Docker volume names:

```text
<COQUI_MODELS_VOLUME>
<COMPOSE_PROJECT>_<COQUI_MODELS_VOLUME>
```

### 1. Check which volume contains XTTS-v2

Run:

```bash
docker run --rm \
  -v <COQUI_MODELS_VOLUME>:/models:ro \
  alpine sh -c "find /models -maxdepth 3 -type d | sort"
```

Then run:

```bash
docker run --rm \
  -v <COMPOSE_PROJECT>_<COQUI_MODELS_VOLUME>:/models:ro \
  alpine sh -c "find /models -maxdepth 3 -type d | sort"
```

Look for this folder:

```text
/models/tts_models--multilingual--multi-dataset--xtts_v2
```

or similar.

---

### 2. Copy the model folder out of the Docker volume

If the model is in your Docker Compose-created volume, for example `<COMPOSE_PROJECT>_<COQUI_MODELS_VOLUME>`, run:

```bash
mkdir -p ./model

docker run --rm \
  -v <COMPOSE_PROJECT>_<COQUI_MODELS_VOLUME>:/root/.local/share/tts:ro \
  -v "$(pwd)/model:/export" \
  alpine sh -c "cp -r /root/.local/share/tts/tts_models--multilingual--multi-dataset--xtts_v2 /export/"
```

If the model is in a manually-created volume, for example `<COQUI_MODELS_VOLUME>`, run this instead:

```bash
mkdir -p ./model

docker run --rm \
  -v <COQUI_MODELS_VOLUME>:/root/.local/share/tts:ro \
  -v "$(pwd)/model:/export" \
  alpine sh -c "cp -r /root/.local/share/tts/tts_models--multilingual--multi-dataset--xtts_v2 /export/"
```

---

### 3. Verify the copied model files

Run:

```bash
ls -lh ./model/tts_models--multilingual--multi-dataset--xtts_v2
```

You should see files similar to:

```text
config.json
model.pth
vocab.json
speakers_xtts.pth
```

The folder may also contain additional model/config files. Keep the full folder intact.

---

## Option B: Download XTTS-v2 directly from Hugging Face

Use this option if the model is not available in your Docker volume.

### 1. Install Hugging Face CLI

```bash
python -m pip install -U "huggingface_hub[cli]"
```

### 2. Create the target model folder

```bash
mkdir -p ./model/tts_models--multilingual--multi-dataset--xtts_v2
cd ./model/tts_models--multilingual--multi-dataset--xtts_v2
```

### 3. Download XTTS-v2

```bash
huggingface-cli download coqui/XTTS-v2 \
  --local-dir . \
  --local-dir-use-symlinks False
```

### 4. Return to the project root

```bash
cd ../../
```

### 5. Verify the downloaded files

```bash
ls -lh ./model/tts_models--multilingual--multi-dataset--xtts_v2
```

Expected key files:

```text
config.json
model.pth
vocab.json
speakers_xtts.pth
```

---

## Create SageMaker `model.tar.gz`

From the directory that contains the `model/` folder, run:

```bash
cd model

tar -czf ../model.tar.gz tts_models--multilingual--multi-dataset--xtts_v2

cd ..
```

---

## Verify the tarball layout

Run:

```bash
tar -tzf model.tar.gz | head -20
```

Expected output should look like:

```text
tts_models--multilingual--multi-dataset--xtts_v2/
tts_models--multilingual--multi-dataset--xtts_v2/config.json
tts_models--multilingual--multi-dataset--xtts_v2/model.pth
tts_models--multilingual--multi-dataset--xtts_v2/vocab.json
tts_models--multilingual--multi-dataset--xtts_v2/speakers_xtts.pth
```

Do **not** package it like this:

```text
model/tts_models--multilingual--multi-dataset--xtts_v2/...
```

because SageMaker extracts the tarball directly into:

```text
/opt/ml/model
```

So the correct final path inside the container should be:

```text
/opt/ml/model/tts_models--multilingual--multi-dataset--xtts_v2/config.json
```

---

## Optional: Check file size

```bash
ls -lh model.tar.gz
```

For a large XTTS model, expect a large archive.

---

## Configure AWS CLI multipart upload settings

The AWS CLI automatically uses multipart upload for large files, but these settings can improve upload performance.

Recommended settings:

```bash
aws configure set default.s3.multipart_threshold 64MB
aws configure set default.s3.multipart_chunksize 128MB
aws configure set default.s3.max_concurrent_requests 20
```

For very fast networks, you can try:

```bash
aws configure set default.s3.max_concurrent_requests 30
```

If your machine or network becomes unstable, reduce it back to:

```bash
aws configure set default.s3.max_concurrent_requests 10
```

---

## Upload `model.tar.gz` to S3

Run:

```bash
aws s3 cp model.tar.gz \
  s3://<YOUR_MODEL_BUCKET>/coqui/xtts-v2/model.tar.gz
```

To time the upload:

```bash
time aws s3 cp model.tar.gz \
  s3://<YOUR_MODEL_BUCKET>/coqui/xtts-v2/model.tar.gz
```

---

## Verify the uploaded object

```bash
aws s3 ls \
  s3://<YOUR_MODEL_BUCKET>/coqui/xtts-v2/model.tar.gz \
  --human-readable
```

Expected result:

```text
YYYY-MM-DD HH:MM:SS   SIZE model.tar.gz
```

---

## Use this S3 path in SageMaker

When creating the SageMaker Model, use this as the model data location:

```text
s3://<YOUR_MODEL_BUCKET>/coqui/xtts-v2/model.tar.gz
```

Container environment variables:

```text
MODEL_PATH=/opt/ml/model/tts_models--multilingual--multi-dataset--xtts_v2
CONFIG_PATH=/opt/ml/model/tts_models--multilingual--multi-dataset--xtts_v2/config.json
USE_CUDA=true
COQUI_TOS_AGREED=1
PORT=8080
```

---

## Troubleshooting

### Problem: SageMaker says `config.json` not found

Check the tarball structure:

```bash
tar -tzf model.tar.gz | head -20
```

If it shows:

```text
model/tts_models--multilingual--multi-dataset--xtts_v2/config.json
```

then the tarball has one extra `model/` folder. Recreate it using:

```bash
cd model

tar -czf ../model.tar.gz tts_models--multilingual--multi-dataset--xtts_v2

cd ..
```

---

### Problem: Upload is slow

Increase concurrency:

```bash
aws configure set default.s3.max_concurrent_requests 20
```

Use larger chunks:

```bash
aws configure set default.s3.multipart_chunksize 128MB
```

Then re-run:

```bash
aws s3 cp model.tar.gz \
  s3://<YOUR_MODEL_BUCKET>/coqui/xtts-v2/model.tar.gz
```

---

### Problem: Upload fails halfway

Re-run the same `aws s3 cp` command. Multipart uploads are handled by the CLI, but if a client-side failure occurs, simply re-running is usually the easiest fix.

Also consider lowering concurrency:

```bash
aws configure set default.s3.max_concurrent_requests 10
```

---

### Problem: Container cannot load on GPU

Check SageMaker endpoint logs in CloudWatch and verify:

```text
USE_CUDA=true
```

Also confirm the endpoint instance type is GPU-based, for example:

```text
<GPU_INSTANCE_TYPE>
```

If the container logs show CUDA is unavailable, the image may not be CUDA/PyTorch GPU compatible, or the endpoint may be running on a CPU instance.

---

## Recommended first production path

Use:

```text
Model: Coqui XTTS-v2 large model
SageMaker model artifact: model.tar.gz
S3 path: s3://<YOUR_MODEL_BUCKET>/coqui/xtts-v2/model.tar.gz
Endpoint type: Real-time inference endpoint
Instance type: <GPU_INSTANCE_TYPE>, for example ml.g5.xlarge
Container env: USE_CUDA=true
Lambda call path: boto3 sagemaker-runtime invoke_endpoint
```
