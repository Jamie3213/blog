import boto3
import json
import logging
import os
import traceback

import yaml

from typing import Any, Dict, List, TypedDict

from aws_lambda_powertools.utilities.typing import LambdaContext
from botocore.exceptions import ClientError


# ------------------------------ Define logging ------------------------------ #

logger = logging.getLogger("deploy_trigger")
logger.setLevel(logging.INFO)

# Format output
formatter = logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")

# Console handler
consoleHandler = logging.StreamHandler()
consoleHandler.setFormatter(formatter)
consoleHandler.setLevel(logging.INFO)

# Add handlers
logger.addHandler(consoleHandler)

# ---------------------------------- Handler --------------------------------- #

class S3EventNotification(TypedDict):
    Records: List[Dict[str, Any]]

class LambdaResponse(TypedDict):
    isBase64Encoded: bool
    statusCode: int
    body: str


def lambda_handler(event: S3EventNotification, context: LambdaContext) -> LambdaResponse:
    S3_BUCKET_NAME = os.environ['S3_BUCKET_NAME']
    S3_OBJECT_KEY = os.environ['S3_OBJECT_KEY']

    logger.info("Reading config file from Amazon S3.")
    s3 = boto3.resource("s3")
    object = s3.Object(S3_BUCKET_NAME, S3_OBJECT_KEY)

    try:
        config_binary = object.get() \
            .get('Body') \
            .read()
    except ClientError:
        logger.error(traceback.format_exc())
        body = json.dumps(f"Failed to read config file '{S3_OBJECT_KEY}' from bucket '{S3_BUCKET_NAME}'.")
        return LambdaResponse(isBase64Encoded=False, statusCode=500, body=body)

    config = yaml.safe_load(config_binary)

    change_file = event['Records'][0] \
        ['s3'] \
        ['object'] \
        ['key'] 

    base_folder = str.split(change_file, "/")[0]
    codebuild_project = config['Folder'][base_folder]

    logger.info(f"Starting CodeBuild project '{codebuild_project}'")
    codebuild = boto3.client("codebuild")
    build = codebuild.start_build(projectName=codebuild_project)
    build_status = build['build']['buildStatus']

    if build_status not in ['SUCCEEDED', 'IN_PROGRESS']:
        msg = f"Failed to CodeBuild project '{codebuild_project}', build status returned '{build_status}'"
        logger.error(msg)
        return LambdaResponse(isBase64Encoded=False, statusCode=500, body=json.dumps(msg))
    else:
        body = json.dumps(f"Build started and returned status '{build_status}'")
        return LambdaResponse(isBase64Encoded=False, statusCode=200, body=body)
