import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { AuthProvider } from "react-oidc-context";

import App from "@/App";
import { authEnabled, oidcConfig } from "@/lib/auth";
import { navigate } from "@/lib/router";

import "./index.css";

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: 1, refetchOnWindowFocus: false } },
});

const app = (
  <QueryClientProvider client={queryClient}>
    <App />
  </QueryClientProvider>
);

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    {authEnabled ? (
      // After the code exchange: drop ?code=&state= from the address bar, go home.
      <AuthProvider {...oidcConfig(() => navigate("/", { replace: true }))}>
        {app}
      </AuthProvider>
    ) : (
      app
    )}
  </StrictMode>,
);
