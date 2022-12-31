#!/bin/bash
#
# AWS EC2: create a snapshot of my EBS volume.
# Requires:	AWS CLI, curl, jq
# Limitation:	only 1 EBS volume attachement
# IAM Role:	Attach AmazonEC2CreateSnapshots custom policy.
#	AmazonEC2CreateSnapshots
#		{
#		    "Version": "2012-10-17",
#		    "Statement": [
#		        {
#		            "Effect": "Allow",
#		            "Action": [
#		                "ec2:CreateSnapshot",
#		                "ec2:DeleteSnapshot",
#		                "ec2:DescribeSnapshots",
#		                "ec2:DescribeInstances",
#		                "ec2:CreateTags"
#		            ],
#		            "Resource": "*"
#		        }
#		    ]
#		}
#
# References:
#	https://gist.github.com/wokamoto/1c53fd9d9ce54c446489
#	http://kumonchu.com/aws/ebs-daily-snapshot/

REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed -e 's/.$//')
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
HOSTNAME=$(hostname -s)
DATE=$(date '+%Y-%m-%d')
AWS="aws --region $REGION"
MIN_SNAPSHOT_AGE_SECONDS=604800 #1w

function get_last_completed_snap() {
  VOL_ID=$($AWS ec2 describe-instances --instance-ids "$INSTANCE_ID" | jq -r '.Reservations[].Instances[].BlockDeviceMappings[].Ebs.VolumeId')
  LAST_SNAP_TS_W_QUOTES=$($AWS ec2 describe-snapshots --owner-ids self --filters "Name=volume-id,Values=$VOL_ID" "Name=status,Values=completed" --query "sort_by(Snapshots, &StartTime)[-1].StartTime")
  echo "DEBUG - LAST_SNAP_TS_W_QUOTES: ${LAST_SNAP_TS_W_QUOTES}"
  LAST_SNAP_TS=$(echo ${LAST_SNAP_TS_W_QUOTES} | tr -d '"')
}

function calculate_seconds_from_last_snap() {
  LAST_SNAP_EPOCH=$(date --date=${LAST_SNAP_TS} +%s)
  CURR_EPOCH=$(date +%s)
  DIFF_SNAP=$((CURR_EPOCH - LAST_SNAP_EPOCH))
}

function check_recent_snap() {
  echo "last snap was ${DIFF_SNAP} ago"
  if [[ ${DIFF_SNAP} -le ${MIN_SNAPSHOT_AGE_SECONDS} ]]; then
    echo "INFO - last snapshot happened less than ${MIN_SNAPSHOT_AGE_SECONDS} ago"
    exit 0
  else
    echo "INFO - last snapshot is more than a week old. Taking a new one"
    exit 1
  fi
}

get_last_completed_snap
calculate_seconds_from_last_snap
check_recent_snap
