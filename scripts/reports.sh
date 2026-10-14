#!/usr/bin/env bash
# Day-to-day commands for the weekly report (see infra/reports.yaml).
#
#   now [WEEK]   send a "build the report" command to the queue (no week: last week)
#   ls           list the reports in the bucket
#   logs         CloudWatch lines of both functions, last hour
#   dlq          how many messages wait in the dead-letter queue
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -f "${ROOT}/.env" ]]; then
  preset="$(export -p)"; set -a
  # shellcheck disable=SC1091
  source "${ROOT}/.env"; set +a; eval "${preset}"
fi
for var in AWS_PROFILE AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
  [[ -n "${!var:-}" ]] || unset "${var}"
done
PROJECT_NAME="${PROJECT_NAME:-spry}"
STACK_NAME="${REPORTS_STACK_NAME:-${PROJECT_NAME}-reports}"
export AWS_DEFAULT_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"

out() {
  aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}

case "${1:-}" in
  now)
    WEEK="${2:-}"
    if [[ -n "${WEEK}" ]]; then
      [[ "${WEEK}" =~ ^[0-9]{4}-W[0-9]{2}$ ]] || { echo "WEEK looks like 2026-W40" >&2; exit 1; }
      BODY="{\"week\": \"${WEEK}\", \"source\": \"manual\"}"
    else
      BODY='{"week": null, "source": "manual"}'
    fi
    aws sqs send-message --queue-url "$(out QueueUrl)" --message-body "${BODY}" \
      --query MessageId --output text >/dev/null
    echo "sent ${BODY}"
    echo "within a minute: make report-ls, make report-logs, and your inbox"
    ;;
  ls)
    # `aws s3 ls` exits 1 when nothing matches - not an error here.
    aws s3 ls "s3://$(out BucketName)/reports/" --recursive || echo "(no reports yet)"
    ;;
  logs)
    for fn in report-builder report-mailer; do
      echo "--- ${PROJECT_NAME}-${fn}"
      aws logs tail "/aws/lambda/${PROJECT_NAME}-${fn}" --since "${SINCE:-1h}" --format short \
        | grep -E 'triggered|wrote|sent|ERROR|Error|Task timed out' || true
    done
    ;;
  dlq)
    aws sqs get-queue-attributes --queue-url "$(out DlqUrl)" \
      --attribute-names ApproximateNumberOfMessages --query Attributes --output table
    ;;
  *)
    echo "usage: $0 now [WEEK] | ls | logs | dlq" >&2; exit 1 ;;
esac
