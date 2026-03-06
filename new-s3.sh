BUCKET_NAME="news-api-$RANDOM-$AWS_REGION"

aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$AWS_REGION"

echo "Created bucket: $BUCKET_NAME"s