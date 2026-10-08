import { ChevronRight } from "lucide-react";

import { AuthControls } from "@/components/auth-controls";

/** Notion-style top bar: breadcrumb on the left, who is signed in on the right. */
export function SiteHeader({ page }: { page: string }) {
  return (
    <header className="sticky top-0 z-20 border-b bg-background/85 backdrop-blur">
      <div className="flex h-11 items-center gap-4 px-4">
        <nav
          aria-label="Breadcrumb"
          className="flex items-center gap-1 text-sm"
        >
          <a href="/" className="flex items-center gap-1">
            <img src="/images/magnolia.png" alt="" className="h-5 w-auto" />
            <span className="font-medium">Spry</span>
          </a>
          <ChevronRight className="size-3.5 text-muted-foreground" />
          <span className="text-muted-foreground">{page}</span>
        </nav>
        <div className="ml-auto">
          <AuthControls />
        </div>
      </div>
    </header>
  );
}
