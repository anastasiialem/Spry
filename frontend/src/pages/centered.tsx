import type { ReactNode } from "react";

import { SiteHeader } from "@/components/site-header";

export function Centered({
  page,
  children,
}: {
  page: string;
  children: ReactNode;
}) {
  return (
    <div className="min-h-svh">
      <SiteHeader page={page} />
      <main className="mx-auto grid max-w-md place-items-center gap-4 px-6 py-24 text-center">
        <img src="/images/magnolia.png" alt="" aria-hidden className="w-24" />
        {children}
      </main>
    </div>
  );
}
