import { WebStorageStateStore } from "oidc-client-ts";
import type { AuthProviderProps } from "react-oidc-context";

/*
 * Values come from the auth stack's outputs at build time
 * (scripts/deploy-frontend.sh, or .env for Compose) - never typed in by hand.
 * None of them is a secret: the app client is public and protected by PKCE.
 */
const authority = import.meta.env.VITE_COGNITO_AUTHORITY as string | undefined;
const clientId = import.meta.env.VITE_COGNITO_CLIENT_ID as string | undefined;
const domain = import.meta.env.VITE_COGNITO_DOMAIN as string | undefined;

export const authEnabled = Boolean(authority && clientId && domain);

/** Must match a Cognito callback URL exactly, trailing slash included. */
export const CALLBACK_PATH = "/auth/callback/";

export function oidcConfig(onSignedIn: () => void): AuthProviderProps {
  return {
    authority: authority!,
    client_id: clientId!,
    redirect_uri: `${window.location.origin}${CALLBACK_PATH}`,
    response_type: "code", // authorization code + PKCE, added by oidc-client-ts
    scope: "openid email profile",
    // Survive a reload or a new tab; tokens expire after an hour anyway.
    userStore: new WebStorageStateStore({ store: window.localStorage }),
    onSigninCallback: onSignedIn,
  };
}

/**
 * Cognito has no standard OIDC end-session endpoint: clear the local session
 * first, then send the browser to Cognito's own /logout.
 */
export function cognitoLogoutUrl(): string {
  const params = new URLSearchParams({
    client_id: clientId!,
    logout_uri: `${window.location.origin}/`,
  });
  return `${domain}/logout?${params}`;
}
