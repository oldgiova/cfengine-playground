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

# Numbers of holding snapshots
# 0: delete no snapshots
SNAPSHOTS_PERIOD=3
# Set extra tags
EXTRA_TAGS="Key=Environment,Value=production"

REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone | sed -e 's/.$//')
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
HOSTNAME=$(hostname -s)
DATE=$(date '+%Y-%m-%d')
AWS="aws --region $REGION"

# Target EBS volume id
VOL_ID=$($AWS ec2 describe-instances --instance-ids "$INSTANCE_ID" | jq -r '.Reservations[].Instances[].BlockDeviceMappings[].Ebs.VolumeId')
if [ -z "$VOL_ID" ]; then
    echo ERROR: no EBS ID.
    exit 1
fi

# create a snapshot
echo Creating snapshot.
SNAPSHOT=$($AWS ec2 create-snapshot --volume-id "$VOL_ID" --description "Created by ec2snapshot ($INSTANCE_ID) from $VOL_ID")
RET=$?
if [ $RET != 0 ]; then
    echo $SNAPSHOT
    echo ERROR: create-snapshot failed:$RET
    exit 2
fi
SNAPSHOT_ID=$(echo $SNAPSHOT | jq -r '.SnapshotId')
$AWS ec2 create-tags --resources "$SNAPSHOT_ID" --tags "Key=Name,Value=$HOSTNAME $DATE" "Key=Hostname,Value=$HOSTNAME" $EXTRA_TAGS
echo $SNAPSHOT_ID \($HOSTNAME $DATE\) created.

# delete old snapshots
if [ $SNAPSHOTS_PERIOD -ge 1 ]; then
    echo Deleting old snapshots.
    SNAPSHOTS=$($AWS ec2 describe-snapshots --owner-ids self --filters "Name=volume-id,Values=$VOL_ID" --query "reverse(sort_by(Snapshots,&StartTime))[$SNAPSHOTS_PERIOD:].[SnapshotId,StartTime]" --output text)
    while read snapshotid starttime; do
	if [ -z "$snapshotid" ]; then
	    continue
	fi
	$AWS ec2 delete-snapshot --snapshot-id "$snapshotid"
	RET=$?
	if [ $RET != 0 ]; then
	    echo ERROR: delete-snapshot $snapshotid failed:$RET
	    exit 3
	fi
	echo $snapshotid \($starttime\) deleted.
    done <<EOF
$SNAPSHOTS
EOF
fi

exit 0

