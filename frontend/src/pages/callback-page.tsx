import { useEffect } from "react";
import { useAuth } from "react-oidc-context";

import { authEnabled } from "@/lib/auth";
import { navigate } from "@/lib/router";
import { Centered } from "@/pages/centered";

/**
 * /auth/callback/ - Cognito sends the browser back here with ?code=&state=.
 * AuthProvider exchanges the code for tokens on its own; onSigninCallback
 * (main.tsx) then goes home. This page only covers the wait and the failures.
 */
function Callback() {
  const auth = useAuth();

  useEffect(() => {
    // Reloaded the callback after signing in: nothing to exchange, go home.
    if (!auth.isLoading && auth.isAuthenticated)
      navigate("/", { replace: true });
  }, [auth.isLoading, auth.isAuthenticated]);

  if (auth.error) {
    return (
      <Centered page="Sign in">
        <p className="text-sm text-destructive">
          Sign-in failed: {auth.error.message}
        </p>
        <a href="/login/" className="text-sm font-medium text-primary">
          Start again
        </a>
      </Centered>
    );
  }
  return (
    <Centered page="Sign in">
      <p className="text-sm text-muted-foreground">Signing you in…</p>
    </Centered>
  );
}

export function CallbackPage() {
  if (!authEnabled) {
    return (
      <Centered page="Sign in">
        <p className="text-sm text-muted-foreground">
          Sign-in is not configured in this build.
        </p>
      </Centered>
    );
  }
  return <Callback />;
}
