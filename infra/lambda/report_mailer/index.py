import logging
import os
from email.message import EmailMessage
from urllib.parse import unquote_plus

import boto3

log = logging.getLogger()
log.setLevel(logging.INFO)
s3 = boto3.client("s3")
ses = boto3.client("sesv2")


def handler(event, context):
    recipients = [r.strip() for r in os.environ["RECIPIENTS"].split(",") if r.strip()]
    for record in event["Records"]:
        bucket = record["s3"]["bucket"]["name"]
        key = unquote_plus(record["s3"]["object"]["key"])
        log.info("report-mailer triggered trigger=s3 event=%s object=s3://%s/%s",
                 record["eventName"], bucket, key)
        if not (key.startswith("reports/") and key.endswith(".csv")):
            continue
        week = key.rsplit("/", 1)[-1].removesuffix(".csv")
        body = s3.get_object(Bucket=bucket, Key=key)["Body"].read()

        msg = EmailMessage()
        msg["Subject"] = f"Spry: meetings report for {week}"
        msg["From"] = os.environ["SENDER"]
        msg["To"] = ", ".join(recipients)
        msg.set_content(
            f"Hello,\n\nthe Spry meetings report for {week} is attached:\n"
            "meetings and hours compared with the week before, the five\n"
            "longest meetings, and totals per account.\n\n- Spry\n"
        )
        msg.add_attachment(body, maintype="text", subtype="csv",
                           filename=f"spry-{week}.csv")
        sent = ses.send_email(
            Destination={"ToAddresses": recipients},
            Content={"Raw": {"Data": msg.as_bytes()}},
        )
        log.info("report-mailer sent %s to %s message_id=%s",
                 key, ",".join(recipients), sent["MessageId"])
