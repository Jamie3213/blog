import json
import logging
import os

import boto3

from typing import Any, Dict, List, TypedDict

from aws_lambda_powertools.utilities.typing import LambdaContext


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

# ---------------------------------- Typing ---------------------------------- #

class S3EventNotification(TypedDict):
  Records: List[Dict[str, Any]]

class LambdaResponse(TypedDict):
  isBase64Encoded: bool
  statusCode: int
  body: str

# ---------------------------------- Handler --------------------------------- #

def lambda_handler(event: S3EventNotification, context: LambdaContext) -> LambdaResponse:
  CODEBUILD_PROJECT = os.environ['CODEBUILD_PROJECT']

  logger.info(f"Starting CodeBuild project {CODEBUILD_PROJECT}.")
  codebuild = boto3.client("codebuild")
  build = codebuild.start_build(projectName=CODEBUILD_PROJECT)
  build_status = build['build']['buildStatus']

  if build_status not in ["SUCCEEDED", "IN_PROGRESS"]:
    msg = f"Failed to CodeBuild project '{CODEBUILD_PROJECT}', build status returned '{build_status}'"
    logger.error(msg)
    return LambdaResponse(isBase64Encoded=False, statusCode=500, body=json.dumps(msg))
  else:
    msg = f"Build started and returned status '{build_status}'"
    logger.info(msg)
    return LambdaResponse(isBase64Encoded=False, statusCode=200, body=json.dumps(msg))
