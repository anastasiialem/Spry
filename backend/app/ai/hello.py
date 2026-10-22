"""make llm-hello - the first call to the parser's model on Bedrock, from the laptop.

Uses your usual AWS credentials (~/.aws). Prints the answer, why it stopped and
the tokens it cost.
"""

import boto3

from app.config import get_settings


def main() -> None:
    settings = get_settings()
    client = boto3.client("bedrock-runtime", region_name=settings.bedrock_region)
    reply = client.converse(
        modelId=settings.parser_model,
        messages=[{"role": "user", "content": [{"text": "In one sentence: what is an ISO week?"}]}],
        inferenceConfig={"maxTokens": 1024},
    )
    content = reply["output"]["message"]["content"]
    print(next((b["text"] for b in content if "text" in b), "(no text)"))
    usage = reply["usage"]
    print(
        f"model={settings.parser_model} stop_reason={reply['stopReason']} "
        f"input_tokens={usage['inputTokens']} output_tokens={usage['outputTokens']}"
    )


if __name__ == "__main__":
    main()
