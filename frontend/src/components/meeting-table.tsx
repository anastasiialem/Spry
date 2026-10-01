import { useQuery } from "@tanstack/react-query";
import {
  AlertCircle,
  CalendarDays,
  CircleDot,
  Clock,
  Hourglass,
  Paperclip,
  Plus,
  Type,
  Users,
} from "lucide-react";

import { StatusSelect } from "@/components/status-select";
import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { api, type Meeting } from "@/lib/api";
import { cn } from "@/lib/utils";

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

const columns = [
  { label: "Title", icon: Type, className: "w-[34%]" },
  { label: "Status", icon: CircleDot },
  { label: "Date", icon: CalendarDays },
  { label: "Time", icon: Clock },
  { label: "Duration", icon: Hourglass },
  { label: "Attendees", icon: Users, className: "text-right" },
];

function NewRow({ onNew }: { onNew: () => void }) {
  return (
    <TableRow className="hover:bg-transparent">
      <TableCell colSpan={columns.length} className="p-0">
        <button
          type="button"
          onClick={onNew}
          className="flex w-full items-center gap-2 px-2 py-2 text-sm text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
        >
          <Plus className="size-4" />
          New meeting
        </button>
      </TableCell>
    </TableRow>
  );
}

export function MeetingTable({
  onNew,
  onOpen,
}: {
  onNew: () => void;
  onOpen: (id: number) => void;
}) {
  const { data, isPending, isError, error, refetch } = useQuery({
    queryKey: ["meetings"],
    queryFn: api.listMeetings,
  });

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

  const now = Date.now();
  const nextId = data?.find((m) => Date.parse(m.starts_at) >= now)?.id;

  return (
    <Table className="border-t">
      <TableHeader>
        <TableRow className="hover:bg-transparent">
          {columns.map(({ label, icon: Icon, className }) => (
            <TableHead key={label} className={cn("font-normal", className)}>
              <span className="inline-flex items-center gap-1.5">
                <Icon className="size-3.5" />
                {label}
              </span>
            </TableHead>
          ))}
        </TableRow>
      </TableHeader>
      <TableBody>
        {isPending &&
          [0, 1, 2].map((i) => (
            <TableRow key={i} className="hover:bg-transparent">
              <TableCell colSpan={columns.length}>
                <Skeleton className="h-5" />
              </TableCell>
            </TableRow>
          ))}

        {data?.length === 0 && (
          <TableRow className="hover:bg-transparent">
            <TableCell
              colSpan={columns.length}
              className="py-10 text-center text-muted-foreground"
            >
              No meetings yet.{" "}
              <button
                type="button"
                onClick={onNew}
                className="font-medium text-primary underline-offset-4 hover:underline"
              >
                Add the first one
              </button>
            </TableCell>
          </TableRow>
        )}

        {data?.map((meeting) => {
          const start = new Date(meeting.starts_at);
          const end = new Date(meeting.ends_at);
          const past = end.getTime() < now;
          return (
            <TableRow
              key={meeting.id}
              className={cn(past && "text-muted-foreground")}
            >
              <TableCell className="font-medium whitespace-normal">
                <span className="inline-flex items-center gap-2">
                  <button
                    type="button"
                    onClick={() => onOpen(meeting.id)}
                    className="text-left underline-offset-4 decoration-border hover:underline"
                  >
                    {meeting.title}
                  </button>
                  {meeting.attachment_count > 0 && (
                    <span
                      className="inline-flex items-center gap-0.5 text-xs font-normal text-muted-foreground"
                      aria-label={`${meeting.attachment_count} files`}
                    >
                      <Paperclip className="size-3" />
                      {meeting.attachment_count}
                    </span>
                  )}
                  {meeting.id === nextId && (
                    <span className="rounded-sm bg-accent px-1.5 py-0.5 text-[11px] font-semibold text-accent-foreground uppercase">
                      Next
                    </span>
                  )}
                </span>
              </TableCell>
              <TableCell>
                <StatusSelect meeting={meeting} />
              </TableCell>
              <TableCell>{dateFmt.format(start)}</TableCell>
              <TableCell className="tabular-nums">
                {timeFmt.format(start)}–{timeFmt.format(end)}
              </TableCell>
              <TableCell>{duration(meeting)}</TableCell>
              <TableCell className="text-right tabular-nums">
                {meeting.attendee_count}
              </TableCell>
            </TableRow>
          );
        })}

        {data && data.length > 0 && <NewRow onNew={onNew} />}
      </TableBody>
    </Table>
  );
}
