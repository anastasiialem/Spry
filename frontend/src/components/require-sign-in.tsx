import { LogIn } from "lucide-react";
import type { ReactNode } from "react";
import { useAuth } from "react-oidc-context";

import { Button } from "@/components/ui/button";
import { authEnabled } from "@/lib/auth";
import { Centered } from "@/pages/centered";

/** Meetings are personal: without a signed-in user there is nothing to show. */
function Gate({ children }: { children: ReactNode }) {
  const auth = useAuth();

  if (auth.isLoading) {
    return (
      <Centered page="Meetings">
        <p className="text-sm text-muted-foreground">Loading…</p>
      </Centered>
    );
  }

  if (!auth.isAuthenticated) {
    return (
      <Centered page="Meetings">
        <h1 className="text-2xl font-bold tracking-tight text-house">
          Your meetings live here
        </h1>
        <p className="text-sm text-muted-foreground">
          Sign in to see and plan your own meetings. Each account has its own
          calendar.
        </p>
        <Button onClick={() => void auth.signinRedirect()}>
          <LogIn />
          Sign in
        </Button>
      </Centered>
    );
  }

  // key: a different user gets a fresh tree (and fresh queries).
  return <div key={auth.user?.profile.sub}>{children}</div>;
}

export function RequireSignIn({ children }: { children: ReactNode }) {
  if (!authEnabled) return <>{children}</>;
  return <Gate>{children}</Gate>;
}
