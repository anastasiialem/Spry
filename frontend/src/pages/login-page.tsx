import { useEffect, useRef } from "react";
import { useAuth } from "react-oidc-context";

import { Button } from "@/components/ui/button";
import { authEnabled } from "@/lib/auth";
import { navigate } from "@/lib/router";
import { Centered } from "@/pages/centered";

/**
 * /login/ - the URL to hand out. The sign-in must START here: oidc-client-ts
 * stores a random state and a PKCE code_verifier before redirecting, and the
 * callback only accepts a code that matches them.
 */
function RedirectToCognito() {
  const auth = useAuth();
  const started = useRef(false);

  useEffect(() => {
    if (auth.isLoading || auth.error || started.current) return;
    if (auth.isAuthenticated) {
      navigate("/", { replace: true });
      return;
    }
    started.current = true; // StrictMode runs effects twice in development
    void auth.signinRedirect();
  }, [auth]);

  if (auth.error) {
    return (
      <Centered page="Sign in">
        <p className="text-sm text-destructive">{auth.error.message}</p>
        <Button onClick={() => void auth.signinRedirect()}>Try again</Button>
      </Centered>
    );
  }
  return (
    <Centered page="Sign in">
      <p className="text-sm text-muted-foreground">Redirecting to sign-in…</p>
    </Centered>
  );
}

export function LoginPage() {
  if (!authEnabled) {
    return (
      <Centered page="Sign in">
        <p className="text-sm text-muted-foreground">
          Sign-in is not configured in this build.
        </p>
      </Centered>
    );
  }
  return <RedirectToCognito />;
}
