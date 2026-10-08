import { LogIn, LogOut } from "lucide-react";
import { useAuth } from "react-oidc-context";

import { Button } from "@/components/ui/button";
import { authEnabled, cognitoLogoutUrl } from "@/lib/auth";

function GoogleMark() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden className="size-3.5">
      <path
        fill="#4285F4"
        d="M22.6 12.2c0-.8-.1-1.5-.2-2.2H12v4.2h5.9a5 5 0 0 1-2.2 3.3v2.7h3.6c2.1-1.9 3.3-4.8 3.3-8z"
      />
      <path
        fill="#34A853"
        d="M12 23c3 0 5.5-1 7.3-2.7l-3.6-2.7c-1 .7-2.2 1.1-3.7 1.1-2.9 0-5.3-1.9-6.2-4.5H2.1v2.8A11 11 0 0 0 12 23z"
      />
      <path
        fill="#FBBC05"
        d="M5.8 14.2a6.6 6.6 0 0 1 0-4.3V7.1H2.1a11 11 0 0 0 0 9.9l3.7-2.8z"
      />
      <path
        fill="#EA4335"
        d="M12 5.4c1.6 0 3.1.6 4.2 1.7l3.2-3.2A11 11 0 0 0 2.1 7.1l3.7 2.8C6.7 7.3 9.1 5.4 12 5.4z"
      />
    </svg>
  );
}

function SignedInOrOut() {
  const auth = useAuth();

  if (auth.isLoading) {
    return <span className="text-xs text-muted-foreground">…</span>;
  }

  if (auth.isAuthenticated) {
    const email = auth.user?.profile.email ?? "";
    const username = auth.user?.profile.preferred_username ?? email;
    return (
      <div className="flex items-center gap-2">
        <span
          aria-hidden
          className="grid size-6 place-items-center rounded-full bg-accent text-xs font-semibold text-accent-foreground uppercase"
        >
          {username.charAt(0)}
        </span>
        <span
          className="hidden max-w-56 truncate text-sm sm:inline"
          title={email}
        >
          <span className="font-medium">{username}</span>
          {email && email !== username && (
            <span className="text-muted-foreground"> · {email}</span>
          )}
        </span>
        <Button
          variant="ghost"
          size="sm"
          onClick={() =>
            void auth
              .removeUser()
              .then(() => window.location.assign(cognitoLogoutUrl()))
          }
        >
          <LogOut />
          Sign out
        </Button>
      </div>
    );
  }

  return (
    <div className="flex items-center gap-2">
      {/* Skips Cognito's page and goes straight to Google. */}
      <Button
        variant="outline"
        size="sm"
        onClick={() =>
          void auth.signinRedirect({
            extraQueryParams: { identity_provider: "Google" },
          })
        }
      >
        <GoogleMark />
        Google
      </Button>
      <Button size="sm" onClick={() => void auth.signinRedirect()}>
        <LogIn />
        Sign in
      </Button>
    </div>
  );
}

export function AuthControls() {
  // Without Cognito settings in the build (e.g. plain `docker compose up`)
  // there is nothing to sign in to, and no AuthProvider above us.
  if (!authEnabled) return null;
  return <SignedInOrOut />;
}
