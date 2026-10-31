import boto3

cognito = boto3.client("cognito-idp")
PROVIDERS = {"google": "Google"}


def users_with_email(pool, email):
    if not email or '"' in email:
        return []
    resp = cognito.list_users(UserPoolId=pool, Filter=f'email = "{email}"')
    return resp["Users"]


def attrs(user):
    return {a["Name"]: a["Value"] for a in user.get("Attributes", [])}


def handler(event, context):
    pool = event["userPoolId"]
    source = event["triggerSource"]
    new = event["request"]["userAttributes"]
    email = (new.get("email") or "").strip().lower()

    if source == "PreSignUp_ExternalProvider":
        if str(new.get("email_verified")).lower() != "true":
            return event
        # userName looks like "google_1234567890": the pool is case
        # insensitive, so it arrives lowercased, while the link call
        # wants the provider's real name ("Google").
        prefix, _, provider_id = event["userName"].partition("_")
        provider = PROVIDERS.get(prefix.lower())
        if not provider or not provider_id:
            return event
        for user in users_with_email(pool, email):
            if user.get("UserStatus") == "EXTERNAL_PROVIDER":
                continue
            if attrs(user).get("email_verified") != "true":
                continue
            cognito.admin_link_provider_for_user(
                UserPoolId=pool,
                DestinationUser={
                    "ProviderName": "Cognito",
                    "ProviderAttributeValue": user["Username"],
                },
                SourceUser={
                    "ProviderName": provider,
                    "ProviderAttributeName": "Cognito_Subject",
                    "ProviderAttributeValue": provider_id,
                },
            )
            print(f"linked {provider} to existing user {user['Username']}")
            break

    elif source == "PreSignUp_SignUp":
        for user in users_with_email(pool, email):
            if user.get("UserStatus") == "EXTERNAL_PROVIDER":
                raise Exception(
                    "This email already signs in with Google - use Sign in with Google"
                )

    return event
