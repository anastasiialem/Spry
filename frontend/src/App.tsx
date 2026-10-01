import { ChevronRight, Plus, Table2 } from "lucide-react";
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";

import { MeetingForm } from "@/components/meeting-form";
import { MeetingPeek } from "@/components/meeting-peek";
import { MeetingStats } from "@/components/meeting-stats";
import { MeetingTable } from "@/components/meeting-table";
import { Schedule } from "@/components/schedule";
import { Button } from "@/components/ui/button";
import { api } from "@/lib/api";

function Flower({ className }: { className?: string }) {
  return (
    <img src="/images/magnolia.png" alt="" aria-hidden className={className} />
  );
}

export default function App() {
  const [formOpen, setFormOpen] = useState(false);
  const [openId, setOpenId] = useState<number | null>(null);

  const { data } = useQuery({
    queryKey: ["meetings"],
    queryFn: api.listMeetings,
  });
  const openMeeting = data?.find((m) => m.id === openId);

  return (
    <div className="min-h-svh">
      {/* Notion-style top bar with a breadcrumb */}
      <header className="sticky top-0 z-20 border-b bg-background/85 backdrop-blur">
        <nav
          aria-label="Breadcrumb"
          className="flex h-11 items-center gap-1 px-4 text-sm"
        >
          <img src="/images/magnolia.png" alt="" className="h-5 w-auto" />
          <span className="font-medium">Spry</span>
          <ChevronRight className="size-3.5 text-muted-foreground" />
          <span className="text-muted-foreground">Meetings</span>
        </nav>
      </header>

      {/* Cover photo */}
      <div className="relative h-56 overflow-hidden">
        <img
          src="/images/swans.jpg"
          alt=""
          aria-hidden
          className="size-full object-cover object-[50%_45%]"
        />
        <div
          aria-hidden
          className="absolute inset-x-0 bottom-0 h-16 bg-gradient-to-b from-transparent to-background/60"
        />
      </div>

      <div className="mx-auto grid max-w-7xl gap-10 px-6 pb-16 sm:px-12 lg:grid-cols-[minmax(0,1fr)_320px]">
        <main className="min-w-0">
          <Flower className="relative -mt-14 mb-1 w-28 drop-shadow-sm" />
          <h1 className="text-4xl font-bold tracking-tight text-house">
            Meetings
          </h1>
          <p className="mt-2 text-muted-foreground">
            Everything on the team calendar, soonest first.
          </p>

          <div className="mt-8">
            <MeetingStats />
          </div>

          <section className="mt-10 grid gap-3" aria-label="Meetings database">
            <div className="flex items-center justify-between gap-4">
              <span className="inline-flex items-center gap-1.5 border-b-2 border-foreground pb-1.5 text-sm font-medium">
                <Table2 className="size-4" />
                Table
              </span>
              <Button size="sm" onClick={() => setFormOpen(true)}>
                <Plus />
                New
              </Button>
            </div>

            {formOpen && <MeetingForm onDone={() => setFormOpen(false)} />}

            <MeetingTable onNew={() => setFormOpen(true)} onOpen={setOpenId} />
          </section>

          {/* Flower divider at the end of the page */}
          <div aria-hidden className="mt-16 flex items-center gap-4">
            <span className="h-px flex-1 bg-border" />
            <Flower className="w-10 opacity-90" />
            <Flower className="w-14 -scale-x-100" />
            <Flower className="w-10 opacity-90" />
            <span className="h-px flex-1 bg-border" />
          </div>
        </main>

        <div className="lg:sticky lg:top-16 lg:mt-8 lg:self-start">
          <Schedule onOpen={setOpenId} />
        </div>
      </div>

      {openMeeting && (
        <MeetingPeek meeting={openMeeting} onClose={() => setOpenId(null)} />
      )}
    </div>
  );
}
