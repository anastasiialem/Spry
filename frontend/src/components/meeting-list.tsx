import { useQuery } from "@tanstack/react-query";
import { AlertCircle, CalendarDays, Clock, Users } from "lucide-react";

import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { api, type Meeting } from "@/lib/api";

const dateFmt = new Intl.DateTimeFormat(undefined, {
  weekday: "short",
  day: "numeric",
  month: "short",
});
const timeFmt = new Intl.DateTimeFormat(undefined, {
  hour: "2-digit",
  minute: "2-digit",
});

function duration(meeting: Meeting): string {
  const minutes = Math.round(
    (Date.parse(meeting.ends_at) - Date.parse(meeting.starts_at)) / 60_000,
  );
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return [h && `${h} h`, m && `${m} min`].filter(Boolean).join(" ");
}

function MeetingCard({ meeting }: { meeting: Meeting }) {
  const start = new Date(meeting.starts_at);
  const end = new Date(meeting.ends_at);
  return (
    <Card className="gap-3 py-4">
      <CardContent className="flex flex-wrap items-center justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate font-medium">{meeting.title}</p>
          <p className="mt-1 flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-muted-foreground">
            <span className="inline-flex items-center gap-1.5">
              <CalendarDays className="size-3.5" />
              {dateFmt.format(start)}
            </span>
            <span className="inline-flex items-center gap-1.5">
              <Clock className="size-3.5" />
              {timeFmt.format(start)}–{timeFmt.format(end)} ·{" "}
              {duration(meeting)}
            </span>
          </p>
        </div>
        <span className="inline-flex items-center gap-1.5 rounded-full bg-accent px-2.5 py-1 text-xs font-medium text-accent-foreground">
          <Users className="size-3.5" />
          {meeting.attendee_count}
        </span>
      </CardContent>
    </Card>
  );
}

export function MeetingList() {
  const { data, isPending, isError, error, refetch } = useQuery({
    queryKey: ["meetings"],
    queryFn: api.listMeetings,
  });

  if (isPending) {
    return (
      <div className="grid gap-3" aria-busy="true">
        {[0, 1, 2].map((i) => (
          <Skeleton key={i} className="h-[74px] rounded-xl" />
        ))}
      </div>
    );
  }

  if (isError) {
    return (
      <Alert variant="destructive">
        <AlertCircle />
        <AlertTitle>Could not load meetings</AlertTitle>
        <AlertDescription>
          <p>{error.message}</p>
          <Button variant="outline" size="sm" onClick={() => refetch()}>
            Retry
          </Button>
        </AlertDescription>
      </Alert>
    );
  }

  if (data.length === 0) {
    return (
      <Card className="items-center py-10 text-center text-sm text-muted-foreground">
        No meetings yet. Add the first one above.
      </Card>
    );
  }

  return (
    <ul className="grid gap-3">
      {data.map((meeting) => (
        <li key={meeting.id}>
          <MeetingCard meeting={meeting} />
        </li>
      ))}
    </ul>
  );
}
