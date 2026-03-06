# Olivier Moriceau
# lambda_function.py
import json
import os
import random
import logging
from datetime import datetime
from zoneinfo import ZoneInfo

import boto3
import requests
from requests.exceptions import RequestException

# logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# AWS clients
s3 = boto3.client("s3")

# ENV variables
NEWS_API_KEY = os.environ.get("NEWS_API_KEY")
NEWS_COUNT = int(os.environ.get("NEWS_COUNT", "10"))
NEWS_TOPICS = os.environ.get("NEWS_TOPICS", "")
S3_BUCKET = os.environ.get("S3_BUCKET_NAME")

BASE_ENDPOINT_NORMAL = "https://newsapi.org/v2/everything"
BASE_ENDPOINT_BROKEN = "https://newsapi.org:444/v2/everything"


def lambda_handler(event, context):
    try:
        if not all([NEWS_API_KEY, NEWS_TOPICS, S3_BUCKET]):
            raise ValueError("Missing required environment variables")

        topics = [t.strip() for t in NEWS_TOPICS.split(",") if t.strip()]
        if len(topics) != 5:
            raise ValueError("NEWS_TOPICS must contain exactly 5 topics")

        # pick a random topic
        topic = random.choice(topics)

        # randomly pick and endpoint
        endpoint = (
            BASE_ENDPOINT_BROKEN
            if random.random() < 0.33
            else BASE_ENDPOINT_NORMAL
        )

        logger.info(f"Selected topic: {topic}")
        logger.info(f"Using endpoint: {endpoint}")

        # API request
        headers = {"X-Api-Key": NEWS_API_KEY}
        params = {
            "q": topic,
            "pageSize": NEWS_COUNT
        }

        try:
            response = requests.get(
                endpoint,
                headers=headers,
                params=params,
                timeout=(3, 10) 
            )
        except RequestException as e:
            logger.error(f"Request failed: {e}")
            return 

        # If The HTTP request fails
        if response.status_code != 200:
            logger.error(
                f"API returned {response.status_code}: {response.text}"
            )
            return

        data = response.json()

        # S3 object key
        timestamp = datetime.now(ZoneInfo("America/Toronto")).strftime("%Y-%m-%dT%H-%M-%S")
        key = f"news/{topic}/{timestamp}.json"

        # store in S3
        s3.put_object(
            Bucket=S3_BUCKET,
            Key=key,
            Body=json.dumps(data),
            ContentType="application/json"
        )

        logger.info(f"Stored news in s3://{S3_BUCKET}/{key}")

        return

    except Exception as e:
        logger.exception("Unhandled exception")